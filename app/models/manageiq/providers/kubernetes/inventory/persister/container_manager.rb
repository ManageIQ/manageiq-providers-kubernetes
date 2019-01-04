class ManageIQ::Providers::Kubernetes::Inventory::Persister::ContainerManager < ManageIQ::Providers::Kubernetes::Inventory::Persister
  include ManageIQ::Providers::Kubernetes::Inventory::Persister::Definitions::ContainerCollections

  def initialize_inventory_collections
    initialize_container_inventory_collections
  end
end
