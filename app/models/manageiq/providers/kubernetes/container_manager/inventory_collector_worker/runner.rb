class ManageIQ::Providers::Kubernetes::ContainerManager::InventoryCollectorWorker::Runner < ManageIQ::Providers::BaseManager::InventoryCollectorWorker::Runner
  attr_reader :pod_watch_stream
  def after_initialize
    super

    watch_options = {}
    @pod_watch_stream = connection.watch_pods(watch_options)
  end

  def do_work
    pod_watch_stream.each do |notice|
      _log.info("EMS [#{ems.id}] Pod: #{notice}")
      heartbeat
    end
  end

  private

  def connection
    @connection ||= ems.connect(:service => "kubernetes", :path => '/api')
  end
end
