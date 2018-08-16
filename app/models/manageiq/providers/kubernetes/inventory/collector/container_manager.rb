class ManageIQ::Providers::Kubernetes::Inventory::Collector::ContainerManager < ManageIQ::Providers::Kubernetes::Inventory::Collector
  def pods
    @pods ||= connection.get_pods
  end

  private

  def connection
    @connection ||= manager.connect(:service => "kubernetes")
  end
end
