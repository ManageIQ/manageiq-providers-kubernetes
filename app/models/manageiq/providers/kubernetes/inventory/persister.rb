class ManageIQ::Providers::Kubernetes::Inventory::Persister < ManageIQ::Providers::Inventory::Persister
  require_nested :ContainerManager
  require_nested :WatchNotice

  def add_collection_directly(collection)
    @collections[collection.name] = collection
  end
end
