require 'openssl'
require 'MiqContainerGroup/MiqContainerGroup'

module ManageIQ::Providers::Kubernetes::ContainerManagerMixin
  extend ActiveSupport::Concern

  DEFAULT_PORT = 6443
  METRICS_ROLES = %w(prometheus hawkular).freeze

  included do
    default_value_for :port do |provider|
      # port is not a column on this table, it's delegated to endpoint.
      # This may confuse `default_value_for` to apply when we do have a port;
      # checking `provider.port` first prevents this from overriding it.
      provider.port || provider.class::DEFAULT_PORT
    end

    supports :streaming_refresh do
      unsupported_reason_add(:streaming_refresh, "Streaming refresh not enabled") unless streaming_refresh_enabled?
    end

    def streaming_refresh_enabled?
      Settings.ems_refresh[emstype.to_sym]&.streaming_refresh
    end
  end

  def monitoring_manager_needed?
    connection_configurations.roles.include?(
      ManageIQ::Providers::Kubernetes::MonitoringManagerMixin::ENDPOINT_ROLE.to_s
    )
  end

  def supports_metrics?
    endpoints.where(:role => METRICS_ROLES).exists?
  end

  module ClassMethods
    def params_for_create
      @params_for_create ||= begin
        {
          :title  => "Configure #{description}",
          :fields => [
            {
              :component  => "text-field",
              :name       => "endpoints.default.hostname",
              :label      => "Hostname",
              :isRequired => true,
              :validate   => [{:type => "required-validator"}]
            },
            {
              :component    => "text-field",
              :name         => "endpoints.default.port",
              :type         => "number",
              :isRequired   => true,
              :initialValue => default_port,
              :validate     => [
                {:type => "required-validator"},
                {:type => "validatorTypes.MIN_NUMBER_VALUE", :includeThreshold => true, :value => 1},
                {:type => "validatorTypes.MAX_NUMBER_VALUE", :includeThreshold => true, :value => 65_535}
              ]
            },
            {
              :component    => "text-field",
              :name         => "endpoints.default.path",
              :label        => "API Path",
              :type         => "hidden",
              :initialValue => "/api"
            },
            {
              :component  => "text-field",
              :name       => "endpoints.default.bearer",
              :label      => "Token",
              :type       => "password",
              :isRequired => true,
              :validate   => [{:type => "required-validator"}]
            },
            {
              :component => "text-field",
              :name      => "endpoints.default.http_proxy",
              :label     => "HTTP Proxy"
            },
            {
              :component => "checkbox",
              :name      => "endpoints.default.verify_ssl",
              :label     => "Verify SSL"
            },
            {
              :component => "text-field",
              :name      => "endpoints.default.ca_file",
              :label     => "Trusted CA Certificates",
            },
          ]
        }.freeze
      end
    end

    def verify_credentials(args)
      default_endpoint = args.dig("endpoints", "default")
      hostname, port = default_endpoint&.values_at("hostname", "port")

      options = default_endpoint&.slice("path", "http_proxy")&.symbolize_keys || {}

      bearer = default_endpoint&.dig("bearer")
      options[:bearer] = MiqPassword.try_decrypt(bearer) if bearer

      options[:ssl_options] = {
        :verify_ssl => default_endpoint&.dig("verify_ssl") ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE,
        :ca_file    => default_endpoint&.dig("ca_file")
      }

      !!raw_connect(hostname, port, options)
    end

    def raw_api_endpoint(hostname, port, path = '')
      URI::HTTPS.build(:host => hostname, :port => port.presence.try(:to_i), :path => path)
    end

    def kubernetes_connect(hostname, port, options)
      require 'kubeclient'

      conn = Kubeclient::Client.new(
        raw_api_endpoint(hostname, port, options[:path]),
        options[:version] || kubernetes_version,
        :ssl_options    => Kubeclient::Client::DEFAULT_SSL_OPTIONS.merge(options[:ssl_options] || {}),
        :auth_options   => kubernetes_auth_options(options),
        :http_proxy_uri => options[:http_proxy] || VMDB::Util.http_proxy_uri,
        :timeouts       => {
          :open => Settings.ems.ems_kubernetes.open_timeout.to_f_with_method,
          :read => Settings.ems.ems_kubernetes.read_timeout.to_f_with_method
        }
      )

      # Test the API endpoint at connect time to prevent exception being raised
      # on first method call
      conn.discover

      conn
    end

    def kubernetes_auth_options(options)
      auth_options = {}
      if options[:username] && options[:password]
        auth_options[:username] = options[:username]
        auth_options[:password] = options[:password]
      end
      auth_options[:bearer_token] = options[:bearer] if options[:bearer]
      auth_options
    end

    def kubernetes_version
      'v1'
    end

    def kubernetes_service_catalog_connect(hostname, port, options)
      options = {:path => '/apis/servicecatalog.k8s.io', :version => service_catalog_api_version}.merge(options)
      kubernetes_connect(hostname, port, options)
    end

    def service_catalog_api_version
      'v1beta1'
    end
  end

  PERF_ROLLUP_CHILDREN = :container_nodes

  def verify_hawkular_credentials
    client = ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::HawkularClient.new(self)
    client.hawkular_try_connect
  end

  def verify_prometheus_credentials
    client = ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusClient.new(self)
    client.prometheus_try_connect
  end

  def verify_prometheus_alerts_credentials
    ensure_monitoring_manager
    monitoring_manager.verify_credentials
  end

  def verify_kubevirt_credentials
    ensure_infra_manager
    options = {
      :token => authentication_token(:kubevirt),
    }
    infra_manager.verify_credentials(:kubevirt, options)
    infra_manager.verify_virt_supported(options)
  end

  # UI methods for determining availability of fields
  def supports_port?
    true
  end

  def supports_security_protocol?
    true
  end

  def api_endpoint
    self.class.raw_api_endpoint(hostname, port)
  end

  def verify_ssl_mode(endpoint = default_endpoint)
    return OpenSSL::SSL::VERIFY_PEER if endpoint.nil? # secure by default

    case endpoint.security_protocol
    when nil, ''
      # Previously providers didn't set security_protocol, defaulted to
      # verify_ssl == 1 (VERIFY_PEER) which wasn't enforced but now is.
      # However, if they explicitly set verify_ssl == 0, we'll respect that.
      endpoint.verify_ssl? ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
    when 'ssl-without-validation'
      OpenSSL::SSL::VERIFY_NONE
    else # 'ssl-with-validation', 'ssl-with-validation-custom-ca', secure by default with unexpected values.
      OpenSSL::SSL::VERIFY_PEER
    end
  end

  def ssl_cert_store(endpoint = default_endpoint)
    # Given missing (nil) endpoint, return nil meaning use system CA bundle
    endpoint.try(:ssl_cert_store)
  end

  def connect(options = {})
    effective_options = connect_options(options)

    self.class.raw_connect(effective_options[:hostname], effective_options[:port], effective_options)
  end

  def connect_options(options = {})
    options.merge(
      :hostname    => options[:hostname] || address,
      :port        => options[:port] || port,
      :user        => options[:user] || authentication_userid(options[:auth_type]),
      :pass        => options[:pass] || authentication_password(options[:auth_type]),
      :bearer      => options[:bearer] || authentication_token(options[:auth_type] || 'bearer'),
      :http_proxy  => self.options ? self.options.fetch_path(:proxy_settings, :http_proxy) : nil,
      :ssl_options => options[:ssl_options] || {
        :verify_ssl => verify_ssl_mode,
        :cert_store => ssl_cert_store
      }
    )
  end

  def authentications_to_validate
    at = [:bearer]
    at << :hawkular if has_authentication_type?(:hawkular)
    at << :prometheus if has_authentication_type?(:prometheus)
    at << :prometheus_alerts if has_authentication_type?(:prometheus_alerts)
    at << :kubevirt if has_authentication_type?(:kubevirt)
    at
  end

  def required_credential_fields(_type)
    [:auth_key]
  end

  def supported_auth_attributes
    %w(userid password auth_key)
  end

  def verify_credentials(auth_type = nil, options = {})
    options = options.merge(:auth_type => auth_type)
    if options[:auth_type].to_s == "hawkular"
      verify_hawkular_credentials
    elsif options[:auth_type].to_s == "prometheus"
      verify_prometheus_credentials
    elsif options[:auth_type].to_s == "prometheus_alerts"
      verify_prometheus_alerts_credentials
    elsif options[:auth_type].to_s == "kubevirt"
      verify_kubevirt_credentials
    else
      with_provider_connection(options, &:api_valid?)
    end
  rescue SocketError,
         Errno::ECONNREFUSED,
         RestClient::ResourceNotFound,
         RestClient::InternalServerError => err
    raise MiqException::MiqUnreachableError, err.message, err.backtrace
  rescue RestClient::Unauthorized   => err
    raise MiqException::MiqInvalidCredentialsError, err.message, err.backtrace
  end

  def ensure_authentications_record
    return if authentications.present?
    update_authentication(:default => {:userid => "_", :save => false})
  end

  def supported_auth_types
    %w(default password bearer hawkular prometheus prometheus_alerts kubevirt)
  end

  def supports_authentication?(authtype)
    supported_auth_types.include?(authtype.to_s)
  end

  def default_authentication_type
    :bearer
  end

  def scan_job_create(entity, userid)
    check_policy_prevent(:request_containerimage_scan, entity, userid, :raw_scan_job_create)
  end

  def raw_scan_job_create(target_class, target_id = nil, userid = nil, target_name = nil)
    raise MiqException::Error, _("target_class must be a class not an instance") if target_class.kind_of?(ContainerImage)
    ManageIQ::Providers::Kubernetes::ContainerManager::Scanning::Job.create_job(
      :userid          => userid,
      :name            => "Container Image Analysis: '#{target_name}'",
      :target_class    => target_class,
      :target_id       => target_id,
      :zone            => my_zone,
      :miq_server_host => MiqServer.my_server.hostname,
      :miq_server_guid => MiqServer.my_server.guid,
      :ems_id          => id,
    )
  end

  # policy_event: the event sent to automate for policy resolution
  # cb_method:    the MiqQueue callback method along with the parameters that is called
  #               when automate process is done and the event is not prevented to proceed by policy
  def check_policy_prevent(policy_event, event_target, userid, cb_method)
    cb = {
      :class_name  => self.class.to_s,
      :instance_id => id,
      :method_name => :check_policy_prevent_callback,
      :args        => [cb_method, event_target.class.name, event_target.id, userid, event_target.name],
      :server_guid => MiqServer.my_guid
    }
    enforce_policy(event_target, policy_event, {}, { :miq_callback => cb }) unless policy_event.nil?
  end

  def check_policy_prevent_callback(*action, _status, _message, result)
    prevented = false
    if result.kind_of?(MiqAeEngine::MiqAeWorkspaceRuntime)

      event = result.get_obj_from_path("/")['event_stream']
      data  = event.attributes["full_data"]
      prevented = data.fetch_path(:policy, :prevented) if data
    end
    prevented ? _log.info(event.attributes["message"].to_s) : send(*action)
  end

  def enforce_policy(event_target, event, inputs = {}, options = {})
    MiqEvent.raise_evm_event(event_target, event, inputs, options)
  end

  SCAN_CONTENT_PATH = '/api/v1/content'

  def scan_entity_create(scan_data)
    client = ext_management_system.connect(:service => 'kubernetes')
    pod_proxy = client.proxy_url(:pod,
                                 scan_data[:pod_name],
                                 scan_data[:pod_port],
                                 scan_data[:pod_namespace])
    nethttp_options = {
      :use_ssl     => true,
      :verify_mode => verify_ssl_mode,
      :cert_store  => ssl_cert_store,
    }
    MiqContainerGroup.new(pod_proxy + SCAN_CONTENT_PATH,
                          nethttp_options,
                          client.headers.stringify_keys,
                          scan_data[:guest_os])
  end

  def annotate(provider_entity_name, ems_indentifier, annotations, container_project_name = nil)
    with_provider_connection do |conn|
      conn.send(
        "patch_#{provider_entity_name}".to_sym,
        ems_indentifier,
        {"metadata" => {"annotations" => annotations}},
        container_project_name # nil is ok for non namespaced entities (e.g images)
      )
    end
  end

  def evaluate_alert(_alert_id, _event)
    # currently only EmsEvents from Prometheus are tested for node alerts,
    # and these should automatically be translated to alerts.
    true
  end

  def queue_metrics_capture
    self.perf_capture_object.perf_capture_all_queue
  end
end
