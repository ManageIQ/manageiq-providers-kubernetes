class ManageIQ::Providers::Kubernetes::Inventory::Persister::ContainerManager < ManageIQ::Providers::Kubernetes::Inventory::Persister
  include ManageIQ::Providers::Kubernetes::Inventory::Persister::Definitions::ContainerCollections

  attr_reader :tag_mapper

  def initialize_inventory_collections
    initialize_container_inventory_collections
    initialize_tag_mapper
  end
end
