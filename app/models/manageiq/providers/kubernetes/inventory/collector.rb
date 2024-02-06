class ManageIQ::Providers::Kubernetes::Inventory::Collector < ManageIQ::Providers::Inventory::Collector
  def connect!(service)
    manager.connect(:service => service)
  end

  def kubernetes_connection
    @kubernetes_connection ||= connect!("kubernetes")
  end
end
