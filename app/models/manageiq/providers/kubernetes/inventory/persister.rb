class ManageIQ::Providers::Kubernetes::Inventory::Persister < ManagerRefresh::Inventory::Persister
  require_nested :ContainerManager
  require_nested :TargetCollection

  def add_collection_directly(collection)
    @collections[collection.name] = collection
  end
end
