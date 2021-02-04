class ManageIQ::Providers::Kubernetes::Inventory::Persister::ContainerManager::WatchNotice < ManageIQ::Providers::Kubernetes::Inventory::Persister::ContainerManager
  def targeted?
    true
  end

  def strategy
    :local_db_find_missing_references
  end
end
