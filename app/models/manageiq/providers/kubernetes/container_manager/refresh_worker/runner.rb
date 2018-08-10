require "kubeclient"

class ManageIQ::Providers::Kubernetes::ContainerManager::RefreshWorker::Runner < ManageIQ::Providers::BaseManager::RefreshWorker::Runner
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

    _log.info("Processing #{notices.length} notices...")
    notices.each do |notice|
    end
    _log.info("Processing #{notices.length} notices...Complete")
  end

  def before_exit(_message, _exit_code)
    stop_watch_threads
  end

  private

  def start_watches
    watch_streams = {}

    kubernetes_connection = ems.connect(:service => ManageIQ::Providers::Kubernetes::ContainerManager.ems_type)
    kubernetes_entity_types.each do |entity|
      watch_method = "watch_#{entity}"

      resource_version = "0"
      watch_streams[entity] = kubernetes_connection.send(watch_method, :resource_version => resource_version)
    end

    openshift_connection = ems.connect
    openshift_entity_types.each do |entity|
      watch_method = "watch_#{entity}"

      resource_version = "0"
      watch_streams[entity] = openshift_connection.send(watch_method, :resource_version => resource_version)
    end

    watch_streams
  end

  def start_watch_threads
    watch_streams.map do |entity_type, watch_stream|
      Thread.new { watch_thread(entity_type, watch_stream) }
    end
  end

  def stop_watch_threads
    self.finish.value = true
    watch_threads.each { |thread| thread.join(10) }
  end

  def watch_thread(entity_type, watch_stream)
    until finish.value
      watch_stream.each do |notice|
        queue.push(notice)
      end
    end
    _log.info("Exiting watch thread")
  rescue => err
    _log.log_backtrace(err)
  end

  def openshift_entity_types
    %w(
      images
      templates
    )
  end

  def kubernetes_entity_types
    %w(
      pods
    )
  end
end
