class KubernetesEventCatcherBase
  # Kinds not modelled in ManageIQ inventory; dropped before parsing regardless
  # of reason. Not operator-configurable — there is no valid use-case for them.
  DISABLED_KINDS = %w[Endpoints EndpointSlice Lease].freeze

  # Fraction of a token's remaining TTL to use as a safety margin before forcing a reconnect.
  TOKEN_REFRESH_MARGIN_RATIO = 0.1

  def initialize(ems, endpoint, authentication, settings, messaging, logger)
    @ems = ems
    @endpoint = endpoint
    @authentication = authentication
    @settings = settings
    @messaging = messaging
    @logger = logger
    ems_settings_key = "ems_#{ems['ems_type']}"
    @filtered_events = (settings['blacklisted_event_names'] || settings.dig('ems', ems_settings_key, 'blacklisted_event_names') || []).map(&:to_s)
  end

  def run!
    notify_started
    logger.info("#{log_prefix} Collecting events...")
    version = nil
    loop do
      client = build_client
      version = client.get_events.resourceVersion if version.nil?
      logger.info("#{log_prefix} Watching from resourceVersion=#{version}")
      version = watch_events(client, version)
    end
  rescue Interrupt
    logger.info("#{log_prefix} Interrupted")
  ensure
    notify_stopping
  end

  def stop!
  end

  private

  def build_client
    @token_expiry = nil # cleared before auth_options so a failed/incomplete fetch never leaves a stale expiry
    client = Kubeclient::Client.new(
      URI::HTTPS.build(:host => endpoint['hostname'], :port => (endpoint['port'] || 443).to_i),
      'v1',
      :ssl_options  => Kubeclient::Client::DEFAULT_SSL_OPTIONS.merge(
        :verify_ssl => verify_ssl_mode,
        :cert_store => ca_cert_store
      ),
      :auth_options => auth_options
    )
    client.discover
    client
  end

  def watch_events(client, version)
    watcher = client.watch_events(version)
    timer   = schedule_token_refresh(watcher)

    watcher.each do |event|
      event_data = EventParser.extract_event_data(event)

      if event_data.empty?
        logger.info("#{log_prefix} Skipping event with no involvedObject (type=#{event.type})")
        version = nil if event.type == "ERROR"
        next
      end

      logger.info("#{log_prefix} Received event kind=#{event_data[:kind]} reason=#{event_data[:reason]} name=#{event_data[:name]} namespace=#{event_data[:namespace]}")

      if filtered?(event_data)
        logger.info("#{log_prefix} Filtered event kind=#{event_data[:kind]} reason=#{event_data[:reason]} event_type=#{event_data[:event_type]}")
        next
      end

      unless event_valid?(event_data)
        logger.info("#{log_prefix} Invalid event (no timestamp) kind=#{event_data[:kind]} reason=#{event_data[:reason]}")
        next
      end

      version = (event_data[:timestamp] && event.dig('metadata', 'resourceVersion')) || version
      publish_events([EventParser.event_to_hash_from_data(event_data, ems['id'])])
      heartbeat
    end
    version
  rescue EOFError, OpenSSL::SSL::SSLError, Kubeclient::HttpError => error
    logger.warn("#{log_prefix} Monitoring connection error, reconnecting... #{error}")
    version
  ensure
    timer&.kill
  end

  attr_reader :ems, :endpoint, :authentication, :settings, :messaging, :logger, :filtered_events

  # Override in subclasses that issue short-lived tokens.
  def token_expiry
    nil
  end

  def schedule_token_refresh(watcher)
    expiry = token_expiry
    return nil if expiry.nil?

    delay = token_refresh_delay(expiry)
    logger.info("#{log_prefix} Token expires in #{(expiry - Time.now.utc).round}s, scheduling refresh in #{delay.round}s")
    Thread.new do
      sleep(delay)
      watcher.finish
    end
  end

  def token_refresh_delay(expiry)
    ttl = expiry - Time.now.utc
    [ttl * (1 - TOKEN_REFRESH_MARGIN_RATIO), 0].max
  end

  def filtered?(event_data)
    DISABLED_KINDS.include?(event_data[:kind]) || filtered_events.include?(event_data[:event_type])
  end

  def event_valid?(event_data)
    !event_data[:timestamp].nil?
  end

  def publish_events(events)
    events.each do |event|
      messaging_client.publish_topic(
        :service => 'manageiq.ems',
        :sender  => ems['id'],
        :event   => event[:event_type],
        :payload => event
      )
    end
  end

  def messaging_client
    @messaging_client ||= ManageIQ::Messaging::Client.open(messaging.merge(:client_ref => "kubernetes-event-catcher-#{ems['id']}"))
  end

  def verify_ssl_mode
    case endpoint['security_protocol']
    when nil, ''
      endpoint['verify_ssl'].to_i != OpenSSL::SSL::VERIFY_NONE ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
    when 'ssl-without-validation'
      OpenSSL::SSL::VERIFY_NONE
    else
      OpenSSL::SSL::VERIFY_PEER
    end
  end

  # Builds an OpenSSL::X509::Store from the endpoint's certificate_authority PEM, or nil if absent.
  # Supports CA chains by splitting on PEM boundaries before loading.
  def ca_cert_store
    pem = endpoint['certificate_authority']
    return nil if pem.nil? || pem.strip.empty?

    store = OpenSSL::X509::Store.new
    pem.split(/(?=-----BEGIN)/).each do |fragment|
      store.add_cert(OpenSSL::X509::Certificate.new(fragment))
    end
    store
  end

  # Override in subclasses to provide provider-specific authentication options.
  # Returns a hash passed directly to Kubeclient as :auth_options.
  def auth_options
    options = {}
    options[:username] = authentication['userid'] if authentication['userid'] && authentication['password']
    options[:password] = authentication['password'] if options[:username]
    options[:bearer_token] = authentication['auth_key'] if authentication['auth_key']
    options
  end

  def notify_started
    if ENV['NOTIFY_SOCKET']
      SdNotify.ready
    elsif ENV['WORKER_HEARTBEAT_FILE']
      heartbeat_to_file
    end
  end

  def heartbeat
    if ENV['NOTIFY_SOCKET']
      SdNotify.watchdog
    elsif ENV['WORKER_HEARTBEAT_FILE']
      heartbeat_to_file
    end
  end

  def notify_stopping
    SdNotify.stopping if ENV['NOTIFY_SOCKET']
  end

  def heartbeat_to_file
    File.write(ENV.fetch('WORKER_HEARTBEAT_FILE'), Time.now.to_i + (settings.dig('worker_settings', 'heartbeat_timeout') || 120))
  end

  # Override in subclasses to customise the log prefix (e.g. to include the subclass name).
  def log_prefix
    'MIQ(ManageIQ::Providers::Kubernetes::ContainerManager::EventCatcher)'
  end
end
