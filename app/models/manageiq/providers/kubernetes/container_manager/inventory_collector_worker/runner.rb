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

      ems_ref = parse_notice_pod_ems_ref(notice.object)

      target = ManagerRefresh::Target.new(
        :manager     => ems,
        :association => :container_groups,
        :manager_ref => ems_ref,
        :options     => {
          :payload => notice.object,
        }.to_json,
      )

      EmsRefresh.queue_refresh(target)

      heartbeat
    end
  end

  private

  def connection
    @connection ||= ems.connect(:service => "kubernetes", :path => '/api')
  end

  def parse_notice_pod_ems_ref(pod)
    pod.metadata.uid
  end
end
