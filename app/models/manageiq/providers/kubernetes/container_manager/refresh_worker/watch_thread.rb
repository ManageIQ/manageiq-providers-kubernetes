class ManageIQ::Providers::Kubernetes::ContainerManager::RefreshWorker::WatchThread
  include Vmdb::Logging

  def self.start!(ems, queue, entity_type, resource_version)
    new(ems.connect_options, ems.class, queue, entity_type, resource_version).tap(&:start!)
  end

  def initialize(connect_options, ems_klass, queue, entity_type, resource_version)
    @connect_options = connect_options
    @ems_klass       = ems_klass
    @entity_type     = entity_type
    @finish          = Concurrent::AtomicBoolean.new
    @queue           = queue

    self.resource_version = resource_version
  end

  def alive?
    thread&.alive?
  end

  def start!
    self.thread = Thread.new { collector_thread }
  end

  def stop!(join_limit = 10.seconds)
    return unless alive?

    finish.make_true
    watch&.finish
    thread&.join(join_limit)
  end

  protected

  attr_accessor :resource_version, :thread, :watch

  private

  attr_reader :connect_options, :ems_klass, :entity_type, :finish, :queue

  def collector_thread
    _log.debug { "Starting watch thread for #{entity_type}" }

    until finish.true?
      self.watch ||= connection(entity_type).send("watch_#{entity_type}", :resource_version => resource_version)

      watch.each do |notice|
        if notice.type == "ERROR"
          message = notice.object&.message
          code    = notice.object&.code
          reason  = notice.object&.reason

          _log.warn("Received an error watching #{entity_type}: [#{code} #{reason}], [#{message}]")
          break
        end

        next if noop?(notice)

        queue.push(notice)
      end

      # If the watch terminated for any reason (410 Gone or just interrupted) then
      # restart with a resourceVersion of nil to start over from the current state
      self.watch = nil
      self.resource_version = nil
    end

    _log.debug { "Exiting watch thread #{entity_type}" }
  rescue => err
    _log.error("Watch thread for #{entity_type} failed: #{err}")
    _log.log_backtrace(err)
  end

  def noop?(_notice)
    # Allow sub-classes to filter notices
    false
  end

  def connection(_entity_type = nil)
    hostname, port = connect_options.values_at(:hostname, :port)
    connect_options[:service] ||= "kubernetes"

    ems_klass.raw_connect(hostname, port, connect_options)
  end
end
