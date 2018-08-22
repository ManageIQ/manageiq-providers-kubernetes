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
end
