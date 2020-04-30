class ManageIQ::Providers::Kubernetes::Inventory::Persister < ManageIQ::Providers::Inventory::Persister
  require_nested :ContainerManager
  require_nested :WatchNotice

  def add_collection_directly(collection)
    @collections[collection.name] = collection
  end

  # ManageIQ::Providers::InventoryCollection.inventory_object_attributes
  # are not defined
  def make_builder_settings(extra_settings = {})
    opts = super
    opts[:auto_inventory_attributes] = false
    opts
  end
end
