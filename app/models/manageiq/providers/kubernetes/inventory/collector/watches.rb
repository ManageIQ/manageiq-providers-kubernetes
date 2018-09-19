class ManageIQ::Providers::Kubernetes::Inventory::Collector::Watches < ManageIQ::Providers::Kubernetes::Inventory::Collector
  attr_accessor :notices
  def initialize(manager, notices)
    self.notices = notices.group_by { |notice| notice.object[:kind] }
    super(manager, nil)
  end

  def namespaces
    @namespaces ||= notices['Namespace']&.map { |notice| notice.object } || []
  end

  def pods
    @pods ||= notices['Pod']&.map { |notice| notice.object } || []
  end

  def cluster_service_classes
    @cluster_service_classes ||= notices['ClusterServiceClass']&.map { |notice| notice.object } || []
  end

  def cluster_service_plans
    @cluster_service_plans ||= notices['ClusterServicePlan']&.map { |notice| notice.object } || []
  end

  def service_instances
    @service_instances ||= notices['ServiceInstance']&.map { |notice| notice.object } || []
  end
end
