module ManageIQ::Providers::Kubernetes::ContainerManager::StreamingRefreshMixin
  include Vmdb::Logging

  attr_accessor :ems, :finish, :watch_threads, :watch_streams, :queue

  def do_before_work_loop
    self.ems = @emss.first

    if ems.supports_streaming_refresh?
      setup_streaming_refresh
    else
      super
    end
  end

  def do_work
    if ems.supports_streaming_refresh?
      do_work_streaming_refresh
    else
      super
    end
  end

  def message_delivery_suspended?
    # If we are using streaming refresh don't dequeue EmsRefresh queue items
    ems.supports_streaming_refresh? || super
  end

  def before_exit(_message, _exit_code)
    super
    stop_watch_threads if ems.supports_streaming_refresh?
  end

  private

  def setup_streaming_refresh
    self.queue  = Queue.new
    self.finish = Concurrent::AtomicBoolean.new(false)

    self.watch_streams = start_watches
    self.watch_threads = start_watch_threads
  end

  def do_work_streaming_refresh
    notices = []

    notices << queue.pop until queue.empty?
    return if notices.empty?

    _log.info("#{log_header} Processing #{notices.length} notices...")
    targeted_refresh(notices)
    _log.info("#{log_header} Processing #{notices.length} notices...Complete")
  end

  def targeted_refresh(notices)
    inventory = ManageIQ::Providers::Kubernetes::Inventory.new(
      watches_persister_klass.new(ems),
      watches_collector_klass.new(ems, notices),
      watches_parser_klass.new
    )

    inventory.parse
    inventory.persister.persist!
  end

  def watches_collector_klass
    ems.class.parent::Inventory::Collector::Watches
  end

  def watches_parser_klass
    ems.class.parent::Inventory::Parser::Watches
  end

  def watches_persister_klass
    ems.class.parent::Inventory::Persister::TargetCollection
  end

  def start_watches
    connection = ems.connect(:service => "kubernetes")
    entity_types.each_with_object({}) do |entity, watch_streams|
      watch_streams[entity] = start_watch(connection, entity)
    end
  end

  def start_watch(connection, entity, resource_version: "0")
    connection.send("watch_#{entity}", :resource_version => resource_version)
  end

  def start_watch_threads
    _log.info("#{log_header} Starting watch threads...")

    threads = watch_streams.each_with_object({}) do |(entity_type, watch_stream), hash|
      hash[entity_type] = Thread.new { watch_thread(entity_type, watch_stream) }
    end

    _log.info("#{log_header} Starting watch threads...Complete")

    threads
  end

  def stop_watch_threads
    safe_log("#{log_header} Stopping watch threads...")
    self.finish.value = true
    watch_threads.each_value { |thread| thread.join(10) }
    safe_log("#{log_header} Stopping watch threads...Complete")
  end

  def watch_thread(entity_type, watch_stream)
    _log.info("#{log_header} #{entity_type} watch thread started")

    until finish.value
      watch_stream.each do |notice|
        queue.push(notice)
      end
    end

    _log.info("#{log_header} #{entity_type} watch thread exiting")
  rescue => err
    _log.log_backtrace(err)
  end

  def entity_types
    %w(
      pods
    )
  end

  def log_header
    "EMS [#{ems.name}], ID: [#{ems.id}]"
  end
end
