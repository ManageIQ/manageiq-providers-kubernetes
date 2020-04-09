class ManageIQ::Providers::Kubernetes::ContainerManager::RefreshWorker::Runner < ManageIQ::Providers::BaseManager::RefreshWorker::Runner
  def after_initialize
    super

    @ems       = ExtManagementSystem.find(@cfg[:ems_id])
    @ems_class = @ems.class
    @finish    = Concurrent::AtomicBoolean.new
    @queue     = Queue.new

    @connect_options            = @ems.connect_options
    @refresher_thread           = nil
    @refresh_notice_threshold   = 100
    @collector_threads          = Concurrent::Map.new
    @resource_version_by_entity = Concurrent::Map.new
    @watches_by_entity          = Concurrent::Map.new
  end

  def do_before_work_loop
    # Prime the entities' resourceVersions by performing an initial full refresh
    full_refresh
  end

  def do_work
    ensure_refresher_thread
    ensure_collector_threads
  end

  def before_exit(_message, _exit_code)
    finish.make_true
    stop_collector_threads
    stop_refresher_thread
  end

  private

  attr_accessor :collector_threads, :refresher_thread
  attr_reader   :connect_options, :ems, :ems_class, :finish, :queue, :refresh_notice_threshold,
                :resource_version_by_entity, :watches_by_entity

  def entity_types
    %w[pods services endpoints replication_controllers nodes namespaces resource_quotas limit_ranges persistent_volumes persistent_volume_claims].freeze
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
      inventory.parse&.persist!

      save_resource_versions(inventory.collector)
    end
  end

  def partial_refresh(notices)
    refresh_block do
    end
  end

  def ensure_refresher_thread
    self.refresher_thread = start_refresher_thread unless refresher_thread&.alive?
  end

  def start_refresher_thread
    Thread.new { refresher }
  end

  def stop_refresher_thread
    queue.push(nil) # Push a nil to unblock the refresher thread
    refresher_thread.join(10)
  end

  def refresher
    loop do
      notices = []

      # Use queue.pop to block until an item is in the queue
      notices << queue.pop

      break if finish.true?

      # Then continue to pop without blocking until the queue is empty
      notices << queue.pop until queue.empty? || notices.count > refresh_notice_threshold
      notices.compact!

      partial_refresh(notices)
    end
  end

  def ensure_collector_threads
    entity_types.each do |entity_type|
      next if collector_threads[entity_type]&.alive?
      collector_threads[entity_type] = start_collector_thread(entity_type)
    end
  end

  def start_collector_thread(entity_type)
    Thread.new { collector_thread(entity_type) }
  end

  def stop_collector_threads
    entity_types.each { |entity_type| stop_collector_thread(entity_type) }
  end

  def stop_collector_thread(entity_type)
    thread = collector_threads[entity_type]
    return unless thread&.alive?

    watches_by_entity[entity_type]&.finish
    thread.join(10)
  end

  def collector_thread(entity_type)
    resource_version = resource_version_by_entity[entity_type]
    watches_by_entity[entity_type] = watch = connection.send("watch_#{entity_type}", :resource_version => resource_version)

    until finish.true?
      watch.each { |notice| queue.push(notice) }
    end
  end

  def connection(_entity_type = nil)
    hostname, port = connect_options.values_at(:hostname, :port)
    connect_options[:service] ||= "kubernetes"

    ems_class.raw_connect(hostname, port, connect_options)
  end

  def inventory_klass
    @inventory_klass ||= "#{ManageIQ::Providers::Inflector.provider_module(ems.class)}::Inventory".constantize
  end

  def log_header
    @log_header ||= "EMS [#{ems.name}], id: [#{ems.id}]"
  end
end
