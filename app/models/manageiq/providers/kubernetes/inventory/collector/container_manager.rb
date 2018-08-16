class ManageIQ::Providers::Kubernetes::Inventory::Collector::ContainerManager < ManageIQ::Providers::Kubernetes::Inventory::Collector
  def namespaces
    @namespaces ||= connection.get_namespaces
  end

  def pods
    @pods ||= connection.get_pods
  end

  private

  def connection
    @connection ||= manager.connect(:service => "kubernetes")
  end
end
