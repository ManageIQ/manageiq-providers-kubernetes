class ManageIQ::Providers::Kubernetes::Inventory::Persister::WatchNotice < ManageIQ::Providers::Kubernetes::Inventory::Persister::ContainerManager
  def targeted?
    true
  end
end
