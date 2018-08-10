module ManageIQ::Providers::Kubernetes::ContainerManager::StreamingRefreshMixin
  include Vmdb::Logging

  attr_accessor :ems, :finish, :watch_threads, :watch_streams, :queue

  def do_before_work_loop
    self.ems   = @emss.first
    self.queue = Queue.new

    self.finish = Concurrent::AtomicBoolean.new(false)
    self.watch_streams = start_watches
    self.watch_threads = start_watch_threads
  end

  def do_work
    notices = []

    notices << queue.pop until queue.empty?
    return if notices.empty?

    _log.info("#{log_header} Processing #{notices.length} notices...")
    # TODO: parse & save notices
    _log.info("#{log_header} Processing #{notices.length} notices...Complete")
  end

  def before_exit(_message, _exit_code)
    stop_watch_threads
  end

  private

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
