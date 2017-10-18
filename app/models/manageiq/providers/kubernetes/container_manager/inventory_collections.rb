module ManageIQ::Providers::Kubernetes::ContainerManager::InventoryCollections
  def targeted
    false
  end

  def strategy
    nil
  end

  def shared_options
    settings_options = options[:inventory_collections].try(:to_hash) || {}

    settings_options.merge(
      :strategy => strategy,
      :targeted => targeted,
    )
  end

  def initialize_inventory_collections
    # TODO: Targeted refreshes will require adjusting the associations / arels. (duh)
    @collections[:container_projects] = ::ManagerRefresh::InventoryCollection.new(
      shared_options.merge(
        :model_class    => ContainerProject,
        :parent         => manager,
        :builder_params => {:ems_id => manager.id},
        :association    => :container_projects,
        :secondary_refs => {:by_name => [:name]},
        :delete_method  => :disconnect_inv,
      )
    )
    initialize_custom_attributes_collections(manager, :container_projects, %w(labels additional_attributes))

    @collections[:container_quotas] = ::ManagerRefresh::InventoryCollection.new(
      shared_options.merge(
        :model_class          => ContainerQuota,
        :parent               => manager,
        :builder_params       => {:ems_id => manager.id},
        :association          => :container_quotas,
        :attributes_blacklist => [:namespace],
      )
    )
    @collections[:container_quota_items] = ::ManagerRefresh::InventoryCollection.new(
      shared_options.merge(
        :model_class => ContainerQuotaItem,
        :parent      => manager,
        :association => :container_quota_items,
        :manager_ref => [:container_quota, :resource],
      )
    )
    @collections[:container_limits] = ::ManagerRefresh::InventoryCollection.new(
      shared_options.merge(
        :model_class          => ContainerLimit,
        :parent               => manager,
        :builder_params       => {:ems_id => manager.id},
        :association          => :container_limits,
        :attributes_blacklist => [:namespace],
      )
    )
    @collections[:container_limit_items] = ::ManagerRefresh::InventoryCollection.new(
      shared_options.merge(
        :model_class => ContainerLimitItem,
        :parent      => manager,
        :association => :container_limit_items,
        :manager_ref => [:container_limit, :resource, :item_type],
      )
    )
    @collections[:container_nodes] = ::ManagerRefresh::InventoryCollection.new(
      shared_options.merge(
        :model_class    => ContainerNode,
        :parent         => manager,
        :builder_params => {:ems_id => manager.id},
        :association    => :container_nodes,
        :secondary_refs => {:by_name => [:name]},
      )
    )
    initialize_container_conditions_collection(manager, :container_nodes)
    initialize_custom_attributes_collections(manager, :container_nodes, %w(labels additional_attributes))

    # polymorphic child of ContainerNode & ContainerImage,
    # but refresh only sets it on nodes.
    @collections[:computer_systems]                  =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class => ComputerSystem,
          :parent      => manager,
          :association => :computer_systems,
          :manager_ref => [:managed_entity],
        )
      )
    @collections[:computer_system_hardwares]         =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class => Hardware,
          :parent      => manager,
          :association => :computer_system_hardwares,
          :manager_ref => [:computer_system],
        )
      )
    @collections[:computer_system_operating_systems] =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class => OperatingSystem,
          :parent      => manager,
          :association => :computer_system_operating_systems,
          :manager_ref => [:computer_system],
        )
      )

    @collections[:container_image_registries] =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class    => ContainerImageRegistry,
          :parent         => manager,
          :builder_params => {:ems_id => manager.id},
          :association    => :container_image_registries,
          :manager_ref    => [:host, :port],
        )
      )
    @collections[:container_images]           =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class    => ContainerImage,
          :parent         => manager,
          :builder_params => {:ems_id => manager.id},
          :association    => :container_images,
          # TODO: old save matches on [:image_ref, :container_image_registry_id]
          # TODO: should match on digest when available
          :manager_ref    => [:image_ref],
          :delete_method  => :disconnect_inv,
        )
      )
    # images have custom_attributes but that's done conditionally in openshift parser

    @collections[:container_groups] =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class          => ContainerGroup,
          :parent               => manager,
          :builder_params       => {:ems_id => manager.id},
          :association          => :container_groups,
          :secondary_refs       => {:by_namespace_and_name => [:namespace, :name]},
          :attributes_blacklist => [:namespace],
          :delete_method        => :disconnect_inv,
        )
      )
    initialize_container_conditions_collection(manager, :container_groups)
    initialize_custom_attributes_collections(manager, :container_groups, %w(labels node_selectors))
    @collections[:container_volumes]      =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class => ContainerVolume,
          :parent      => manager,
          :association => :container_volumes,
          :manager_ref => [:parent, :name],
        )
      )
    @collections[:containers]             =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class    => Container,
          :parent         => manager,
          :builder_params => {:ems_id => manager.id},
          :association    => :containers,
          # parser sets :ems_ref => "#{pod_id}_#{container.name}_#{container.image}"
          :delete_method  => :disconnect_inv,
        )
      )
    @collections[:container_port_configs] =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class => ContainerPortConfig,
          :parent      => manager,
          :association => :container_port_configs,
          # parser sets :ems_ref => "#{pod_id}_#{container_name}_#{port_config.containerPort}_#{port_config.hostPort}_#{port_config.protocol}"
        )
      )
    @collections[:container_env_vars]     =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class => ContainerEnvVar,
          :parent      => manager,
          :association => :container_env_vars,
          # TODO: old save matches on all :name, :value, :field_path - does this matter?
          :manager_ref => [:container, :name],
        )
      )
    @collections[:security_contexts]      =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class => SecurityContext,
          :parent      => manager,
          :association => :security_contexts,
          :manager_ref => [:resource],
        )
      )

    @collections[:container_replicators] =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class          => ContainerReplicator,
          :parent               => manager,
          :builder_params       => {:ems_id => manager.id},
          :association          => :container_replicators,
          :secondary_refs       => {:by_namespace_and_name => [:namespace, :name]},
          :attributes_blacklist => [:namespace],
        )
      )
    initialize_custom_attributes_collections(manager, :container_replicators, %w(labels selectors))

    @collections[:container_services] =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class          => ContainerService,
          :parent               => manager,
          :builder_params       => {:ems_id => manager.id},
          :association          => :container_services,
          :secondary_refs       => {:by_namespace_and_name => [:namespace, :name]},
          :attributes_blacklist => [:namespace],
          :saver_strategy       => :default # TODO(perf) Can't use batch strategy because of usage of M:N container_groups relation
        )
      )
    initialize_custom_attributes_collections(manager, :container_services, %w(labels selectors))
    @collections[:container_service_port_configs] =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class => ContainerServicePortConfig,
          :parent      => manager,
          :association => :container_service_port_configs,
          :manager_ref => [:ems_ref, :protocol] # TODO(lsmola) make protocol part of the ems_ref?
        )
      )

    @collections[:container_routes] =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class          => ContainerRoute,
          :parent               => manager,
          :builder_params       => {:ems_id => manager.id},
          :association          => :container_routes,
          :attributes_blacklist => [:namespace, :tags],
        )
      )
    initialize_custom_attributes_collections(manager, :container_routes, %w(labels))

    @collections[:container_templates] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class          => ContainerTemplate,
        :parent               => manager,
        :builder_params       => {:ems_id => manager.id},
        :association          => :container_templates,
        :attributes_blacklist => [:namespace],
      )
    initialize_custom_attributes_collections(manager, :container_templates, %w(labels))
    @collections[:container_template_parameters] =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class => ContainerTemplateParameter,
          :parent      => manager,
          :association => :container_template_parameters,
          :manager_ref => [:container_template, :name],
        )
      )

    @collections[:container_builds] =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class          => ContainerBuild,
          :parent               => manager,
          :builder_params       => {:ems_id => manager.id},
          :association          => :container_builds,
          :attributes_blacklist => [:tags],
          :secondary_refs       => {:by_namespace_and_name => [:namespace, :name]},
        )
      )
    initialize_custom_attributes_collections(manager, :container_builds, %w(labels))
    @collections[:container_build_pods] =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class    => ContainerBuildPod,
          :parent         => manager,
          :builder_params => {:ems_id => manager.id},
          :association    => :container_build_pods,
          # TODO: convert namespace column -> container_project_id?
          :manager_ref    => [:namespace, :name],
          :secondary_refs => {:by_namespace_and_name => [:namespace, :name]},
        )
      )
    initialize_custom_attributes_collections(manager, :container_build_pods, %w(labels))

    @collections[:persistent_volumes]       =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class    => PersistentVolume,
          :parent         => manager,
          :builder_params => {:parent => manager},
          :association    => :persistent_volumes,
        )
      )
    @collections[:persistent_volume_claims] =
      ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class          => PersistentVolumeClaim,
          :parent               => manager,
          :builder_params       => {:ems_id => manager.id},
          :association          => :persistent_volume_claims,
          :secondary_refs       => {:by_namespace_and_name => [:namespace, :name]},
          :attributes_blacklist => [:namespace],
        )
      )
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
          :arel        => query,
          :manager_ref => [:container_entity, :name],
        )
      )
  end

  # CustomAttribute is polymorphic child of many models
  def initialize_custom_attributes_collections(manager, association, sections)
    relation = manager.public_send(association)
    sections.each do |section|
      query = CustomAttribute.where(
        :resource_type => relation.model.base_class.name,
        :resource_id   => relation,
        :section       => section.to_s
      )
      @collections[[:custom_attributes_for, relation.model.base_class.name, section.to_s]] =
        ::ManagerRefresh::InventoryCollection.new(
          shared_options.merge(
            :model_class                  => CustomAttribute,
            :arel                         => query,
            :manager_ref                  => [:resource, :section, :name],
            :parent_inventory_collections => [association]
          )
        )
    end
  end
end
