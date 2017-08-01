module ManageIQ::Providers
  class Kubernetes::MonitoringManager < ManageIQ::Providers::MonitoringManager
    require_nested :EventCatcher

    include ManageIQ::Providers::Kubernetes::MonitoringManagerMixin

    belongs_to :parent_manager,
               :foreign_key => :parent_ems_id,
               :class_name  => "ManageIQ::Providers::Kubernetes::ContainerManager",
               :inverse_of  => :monitoring_manager

    def self.ems_type
      @ems_type ||= "kubernetes_monitor".freeze
    end

    def self.description
      @description ||= "Kubernetes Monitor".freeze
    end

    def self.event_monitor_class
      ManageIQ::Providers::Kubernetes::MonitoringManager::EventCatcher
    end
  end
end
