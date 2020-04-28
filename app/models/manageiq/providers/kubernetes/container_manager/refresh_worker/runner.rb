class ManageIQ::Providers::Kubernetes::ContainerManager::RefreshWorker::Runner < ManageIQ::Providers::BaseManager::RefreshWorker::Runner
  def after_initialize
    super

    @ems    = ExtManagementSystem.find(@cfg[:ems_id])
    @finish = Concurrent::AtomicBoolean.new
    @queue  = Queue.new

    @refresher_thread           = nil
    @refresh_notice_threshold   = 100
    @collector_threads          = {}
    @resource_version_by_entity = {}
  end

  def do_before_work_loop
    # Prime the entities' resourceVersions by performing an initial full refresh
    # if we're using streaming refresh, otherwise queue an initial full the standard way
    streaming_refresh? ? full_refresh : super
  end

  def do_work
    streaming_refresh? ? ensure_threads : stop_threads

    super
  end

  def deliver_queue_message(msg)
    # If we are using streaming refresh a user initiated full refresh should
    # do a full refresh and restart the collector threads
    if streaming_refresh?
      super { restart_inventory_collector if full_refresh_queued?(msg) }
    else
      super
    end
  end

  def before_exit(_message, _exit_code)
    stop_threads if streaming_refresh?
  end

  private

  attr_accessor :collector_threads, :refresher_thread
  attr_reader   :ems, :finish, :queue, :refresh_notice_threshold, :resource_version_by_entity

  def restart_inventory_collector
    stop_collector_threads
    full_refresh
    ensure_collector_threads
  end

  def kubernetes_entity_types
    %w[pods replication_controllers nodes namespaces resource_quotas limit_ranges persistent_volumes persistent_volume_claims].freeze
  end

  def entity_types
    kubernetes_entity_types
  end

  def refresh_block
    yield

    ems.update!(:last_refresh_error => nil, :last_refresh_date => Time.now.utc)
  rescue => err
    _log.error("#{log_header} Refresh failed: #{err}")
    _log.log_backtrace(err)
    ems.update!(:last_refresh_error => err.to_s, :last_refresh_date => Time.now.utc)
  end

  def save_resource_versions(collector)
    entity_types.each { |entity| resource_version_by_entity[entity] = collector.send(entity).resourceVersion }
  end

  def full_refresh
    refresh_block do
      inventory = inventory_klass.build(ems, nil)
      inventory.parse
      inventory.persister.persist!

      save_resource_versions(inventory.collector)
    end
  end

  def partial_refresh(notices)
    refresh_block do
      collector = inventory_klass::Collector::WatchNotice.new(ems, notices)
      persister = inventory_klass::Persister::WatchNotice.new(ems, nil)
      parser    = inventory_klass::Parser::WatchNotice.new

      parser.collector = collector
      parser.persister = persister
      parser.parse
      persister.persist!
    end
  end

  def ensure_threads
    ensure_refresher_thread
    ensure_collector_threads
  end

  def stop_threads
    finish.make_true
    stop_collector_threads
    stop_refresher_thread
  end

  def ensure_refresher_thread
    self.refresher_thread = start_refresher_thread unless refresher_thread&.alive?
  end

  def start_refresher_thread
    Thread.new { refresher }
  end

  def stop_refresher_thread
    return unless refresher_thread&.alive?

    queue.push(nil) # Push a nil to unblock the refresher thread
    refresher_thread.join(10)
  end

  def refresher
    _log.debug("#{log_header} Starting refresher thread")

    loop do
      notices = []

      # Use queue.pop to block until an item is in the queue
      notices << queue.pop

      break if finish.true?

      # Then continue to pop without blocking until the queue is empty
      notices << queue.pop until queue.empty? || notices.count > refresh_notice_threshold
      notices.compact!

      _log.debug { "#{log_header} Refreshing #{notices.count} total notices" }
      notices_by_kind = notices.group_by { |notice| notice.object.kind }
      notices_by_kind.each do |kind, notices|
        _log.debug { "#{log_header}   #{kind}: #{notices.count} notices" }
      end
      partial_refresh(notices)
    end

    _log.debug { "#{log_header} Exiting refresher thread" }
  end

  def ensure_collector_threads
    entity_types.each do |entity_type|
      next if collector_threads[entity_type]&.alive?

      collector_threads[entity_type] = start_collector_thread(entity_type)
    end
  end

  def start_collector_thread(entity_type)
    ems.class::RefreshWorker::WatchThread.start!(ems, queue, entity_type, resource_version_by_entity[entity_type])
  end

  def stop_collector_threads
    collector_threads.each_value(&:stop!)
  end

  def refresh_queued?(msg)
    msg.class_name == "EmsRefresh" && msg.method_name == "refresh"
  end

  def full_refresh_queued?(msg)
    refresh_queued?(msg) && msg.data.any? { |klass, _id| klass == ems.class.name }
  end

  def streaming_refresh?
    refresher_options&.streaming_refresh
  end

  def refresher_options
    Settings.ems_refresh[ems.emstype]
  end

  def inventory_klass
    @inventory_klass ||= "#{ManageIQ::Providers::Inflector.provider_module(ems.class)}::Inventory".constantize
  end

  def log_header
    @log_header ||= "EMS [#{ems.name}], id: [#{ems.id}]"
  end
end
