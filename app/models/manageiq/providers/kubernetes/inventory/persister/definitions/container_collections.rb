module ManageIQ::Providers::Kubernetes::Inventory::Persister::Definitions::ContainerCollections
  extend ActiveSupport::Concern

  def initialize_container_inventory_collections
    %i(containers
       container_builds
       container_build_pods
       container_env_vars
       container_groups
       container_images
       container_image_registries
       container_limits
       container_limit_items
       container_nodes
       container_port_configs
       container_projects
       container_quotas
       container_quota_scopes
       container_quota_items
       container_volumes
       container_replicators
       container_routes
       container_services
       container_service_port_configs
       container_templates
       container_template_parameters
       computer_systems
       computer_system_hardwares
       computer_system_operating_systems
       persistent_volumes
       persistent_volume_claims
       security_contexts).each do |name|

      add_collection(container, name)
    end



    initialize_custom_attributes_collections(@collections[:container_projects], %w(labels additional_attributes))
    initialize_taggings_collection(@collections[:container_projects])

    initialize_container_conditions_collection(manager, :container_nodes)
    initialize_custom_attributes_collections(@collections[:container_nodes], %w(labels additional_attributes))
    initialize_taggings_collection(@collections[:container_nodes])

    initialize_container_conditions_collection(manager, :container_groups)
    initialize_custom_attributes_collections(@collections[:container_groups], %w(labels node_selectors))
    initialize_taggings_collection(@collections[:container_groups])

    initialize_custom_attributes_collections(@collections[:container_replicators], %w(labels selectors))
    initialize_taggings_collection(@collections[:container_replicators])

    initialize_custom_attributes_collections(@collections[:container_services], %w(labels selectors))
    initialize_taggings_collection(@collections[:container_services])

    initialize_custom_attributes_collections(@collections[:container_routes], %w(labels))
    initialize_taggings_collection(@collections[:container_routes])

    initialize_custom_attributes_collections(@collections[:container_templates], %w(labels))
    initialize_taggings_collection(@collections[:container_templates])

    initialize_custom_attributes_collections(@collections[:container_builds], %w(labels))
    initialize_taggings_collection(@collections[:container_builds])

    initialize_custom_attributes_collections(@collections[:container_build_pods], %w(labels))

  end

  # ContainerCondition is polymorphic child of ContainerNode & ContainerGroup.
  def initialize_container_conditions_collection(manager, association)
    relation = manager.public_send(association)
    query = ContainerCondition.where(
      :container_entity_type => relation.model.base_class.name,
      :container_entity_id   => relation, # nested SELECT. TODO: compare to a JOIN.
      )
    @collections[[:container_conditions_for, relation.model.base_class.name]] =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class => ContainerCondition,
          :name        => "container_conditions_for_#{association}".to_sym,
          :arel        => query,
          :manager_ref => [:container_entity, :name],
          )
      )
  end

  # CustomAttribute is polymorphic child of many models
  def initialize_custom_attributes_collections(parent_collection, sections)
    type = parent_collection.model_class.base_class.name
    relation = parent_collection.full_collection_for_comparison
    sections.each do |section|
      query = CustomAttribute.where(
        :resource_type => type,
        :resource_id   => relation,
        :section       => section.to_s
      )
      @collections[[:custom_attributes_for, type, section.to_s]] =
        ::ManagerRefresh::InventoryCollection.new(
          shared_options.merge(
            :model_class                  => CustomAttribute,
            :name                         => "custom_attributes_for_#{parent_collection.name}_#{section}".to_sym,
            :arel                         => query,
            :manager_ref                  => [:resource, :section, :name],
            :parent_inventory_collections => [parent_collection.name],
            )
        )
    end
  end

  def initialize_taggings_collection(parent_collection)
    type = parent_collection.model_class.base_class.name
    relation = parent_collection.full_collection_for_comparison
    query = Tagging.where(
      :taggable_type => type,
      :taggable_id   => relation,
      ).joins(:tag).merge(Tag.controlled_by_mapping)

    @collections[[:taggings_for, type]] =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class                  => Tagging,
          :name                         => "taggings_for_#{parent_collection.name}".to_sym,
          :arel                         => query,
          :manager_ref                  => [:taggable, :tag],
          :parent_inventory_collections => [parent_collection.name],
          )
      )
  end

end