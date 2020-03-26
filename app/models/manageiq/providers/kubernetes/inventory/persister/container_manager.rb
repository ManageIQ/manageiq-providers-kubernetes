class ManageIQ::Providers::Kubernetes::Inventory::Persister::ContainerManager < ManageIQ::Providers::Kubernetes::Inventory::Persister
  include ManageIQ::Providers::Kubernetes::Inventory::Persister::Definitions::ContainerCollections

  attr_reader :tag_mapper

  def initialize_inventory_collections
    initialize_container_inventory_collections

    @tag_mapper = ContainerLabelTagMapping.mapper
    add_collection_directly(@tag_mapper.tags_to_resolve_collection)
  end
end
