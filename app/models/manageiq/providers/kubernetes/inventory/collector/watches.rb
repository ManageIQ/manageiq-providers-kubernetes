class ManageIQ::Providers::Kubernetes::Inventory::Collector::Watches < ManageIQ::Providers::Kubernetes::Inventory::Collector
  attr_accessor :notices
  def initialize(manager, notices)
    self.notices = notices.group_by { |notice| notice.object[:kind] }
    super(manager, nil)
  end

  def namespace_notices
    @namespace_notices ||= notices['Namespace'] || []
  end

  def pod_notices
    @pod_notices ||= notices['Pod'] || []
  end

  def cluster_service_class_notices
    @cluster_service_class_notices ||= notices['ClusterServiceClass'] || []
  end

  def cluster_service_plan_notices
    @cluster_service_plan_notices ||= notices['ClusterServicePlan'] || []
  end

  def service_instance_notices
    @service_instances ||= notices['ServiceInstance'] || []
  end
end
