module ManageIQ::Providers::Kubernetes::Inventory::Persister::Definitions::ContainerCollections
  extend ActiveSupport::Concern

  def initialize_container_inventory_collections
    %i(containers
       container_builds
       container_build_pods
       container_env_vars
       container_groups
       container_image_registries
       container_images
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

    initialize_container_conditions

    initialize_custom_attributes

    initialize_taggings
  end

  protected

  def initialize_container_conditions
    %i(container_groups
       container_nodes).each do |name|
      add_container_conditions(manager, name)
    end
  end

  def initialize_custom_attributes
    %i(container_nodes
       container_projects).each do |name|
      add_custom_attributes(name, %w(labels additional_attributes))
    end

    %i(container_groups).each do |name|
      add_custom_attributes(name, %w(labels node_selectors))
    end

    %i(container_replicators
       container_services).each do |name|
      add_custom_attributes(name, %w(labels selectors))
    end

    %i(container_builds
       container_build_pods
       container_routes
       container_templates).each do |name|
      add_custom_attributes(name, %w(labels))
    end
  end

  def initialize_taggings
    %i(container_builds
       container_groups
       container_nodes
       container_projects
       container_replicators
       container_routes
       container_services
       container_templates).each do |name|

      add_taggings(name)
    end
  end

  # ContainerCondition is polymorphic child of ContainerNode & ContainerGroup.
  # @param manager [ExtManagementSystem]
  # @param association [Symbol]
  def add_container_conditions(manager, association)
    relation = manager.public_send(association)
    query = ContainerCondition.where(
      :container_entity_type => relation.model.base_class.name,
      :container_entity_id   => relation, # nested SELECT. TODO: compare to a JOIN.
    )

    add_collection(container,
                   [:container_conditions_for, relation.model.base_class.name],
                   {},
                   {:auto_inventory_attributes => false}) do |builder|

      builder.add_properties(
        :model_class => ContainerCondition,
        :association => nil,
        :name        => "container_conditions_for_#{association}".to_sym,
        :arel        => query,
        :manager_ref => %i(container_entity name),
      )
    end
  end

  # CustomAttribute is polymorphic child of many models
  # @param parent [Symbol]
  # @param sections [Array<String>]
  def add_custom_attributes(parent, sections)
    parent_collection = @collections[parent]

    type = parent_collection.model_class.base_class.name
    relation = parent_collection.full_collection_for_comparison

    sections.each do |section|
      query = ::CustomAttribute.where(
        :resource_type => type,
        :resource_id   => relation,
        :section       => section.to_s
      )

      add_collection(container, [:custom_attributes_for, type, section.to_s], {}, { :auto_inventory_attributes => false }) do |builder|
        builder.add_properties(
          :model_class                  => ::CustomAttribute,
          :association                  => nil,
          :name                         => "custom_attributes_for_#{parent_collection.name}_#{section}".to_sym,
          :arel                         => query,
          :manager_ref                  => %i(resource section name),
          :parent_inventory_collections => [parent_collection.name],
        )
      end
    end
  end

  # @param parent_name [Symbol]
  def add_taggings(parent_name)
    parent_collection = @collections[parent_name]
    type = parent_collection.model_class.base_class.name
    relation = parent_collection.full_collection_for_comparison

    query = Tagging.where(
      :taggable_type => type,
      :taggable_id   => relation,
    ).joins(:tag).merge(Tag.controlled_by_mapping)

    add_collection(container, [:taggings_for, type], {}, {:auto_inventory_attributes => false}) do |builder|
      builder.add_properties(
        :model_class                  => ::Tagging,
        :association                  => nil,
        :name                         => "taggings_for_#{parent_collection.name}".to_sym,
        :arel                         => query,
        :manager_ref                  => %i(taggable tag),
        :parent_inventory_collections => [parent_collection.name],
      )
    end
  end
end
