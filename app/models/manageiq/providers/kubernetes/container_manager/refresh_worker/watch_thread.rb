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

  private

  attr_reader :connect_options, :ems_klass, :entity_type, :finish, :queue
  attr_accessor :resource_version, :thread, :watch

  def collector_thread
    _log.debug("Starting watch thread for #{entity_type}")

    until finish.true?
      self.watch ||= connection(entity_type).send("watch_#{entity_type}", :resource_version => resource_version)

      watch.each do |notice|
        # If we get a 410 gone with this resource version break out and restart
        # the watch
        if notice.kind == "Status" && notice.code == 410
          _log.warn("Caught 410 Gone, restarting watch")
          break
        end

        queue.push(notice)
      end

      # If the watch terminated for any reason (410 Gone or just interrupted) then
      # restart with a resourceVersion of nil to start over from the current state
      self.watch = nil
      self.resource_version = nil
    end

    _log.debug("Exiting watch thread #{entity_type}")
  rescue => err
    _log.error("Watch thread for #{entity_type} failed: #{err}")
    _log.log_backtrace(err)
  end

  def connection(_entity_type = nil)
    hostname, port = connect_options.values_at(:hostname, :port)
    connect_options[:service] ||= "kubernetes"

    ems_klass.raw_connect(hostname, port, connect_options)
  end
end
