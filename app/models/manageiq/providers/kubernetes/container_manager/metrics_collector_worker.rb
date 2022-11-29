module ManageIQ::Providers
  class Kubernetes::ContainerManager::MetricsCollectorWorker < BaseManager::MetricsCollectorWorker
    require_nested :Runner

    self.default_queue_name = "kubernetes"

    def friendly_name
      @friendly_name ||= "C&U Metrics Collector for Kubernetes"
    end

    # Override PerEmsTypeWorkerMixin.all_valid_ems_in_zone to limit metrics collection
    def self.all_ems_in_zone
      super.select do |ems|
        ems.supports?(:metrics).tap do |supported|
          _log.info("Skipping [#{ems.name}] since it has no metrics endpoint") unless supported
        end
      end
    end
  end
end
