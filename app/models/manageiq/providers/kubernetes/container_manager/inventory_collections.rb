module ManageIQ::Providers::Kubernetes::ContainerManager::InventoryCollections
  def targeted
    false
  end

  def strategy
    nil
  end

  def saver_strategy
    :default
  end

  def shared_options
    {
      :strategy       => strategy,
      :targeted       => targeted,
      :saver_strategy => saver_strategy
    }
  end

  def initialize_inventory_collections(ems)
    # TODO: Targeted refreshes will require adjusting the associations / arels. (duh)
    @collections = @inv_collections = {}
    @inv_collections[:container_projects] = ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
      :model_class    => ContainerProject,
      :parent         => ems,
      :builder_params => {:ems_id => ems.id},
      :association    => :container_projects,
      :secondary_refs => {:by_name => [:name]},
    ))
    @inv_collections[:container_quotas] = ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
      :model_class          => ContainerQuota,
      :parent               => ems,
      :builder_params       => {:ems_id => ems.id},
      :association          => :container_quotas,
      :attributes_blacklist => [:namespace],
    ))
    @inv_collections[:container_quota_items] = ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
      :model_class => ContainerQuotaItem,
      :parent      => ems,
      :association => :container_quota_items,
      :manager_ref => [:container_quota, :resource],
    ))
    @inv_collections[:container_limits] = ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
      :model_class          => ContainerLimit,
      :parent               => ems,
      :builder_params       => {:ems_id => ems.id},
      :association          => :container_limits,
      :attributes_blacklist => [:namespace],
    ))
    @inv_collections[:container_limit_items] = ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
      :model_class => ContainerLimitItem,
      :parent      => ems,
      :association => :container_limit_items,
      :manager_ref => [:container_limit, :resource, :item_type],
    ))
    @inv_collections[:container_nodes] = ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
      :model_class    => ContainerNode,
      :parent         => ems,
      :builder_params => {:ems_id => ems.id},
      :association    => :container_nodes,
      :secondary_refs => {:by_name => [:name]},
    ))
    initialize_container_conditions_collection(ems.container_nodes)
    initialize_custom_attributes_collections(ems.container_nodes, %w(labels additional_attributes))

    # polymorphic child of ContainerNode & ContainerImage,
    # but refresh only sets it on nodes.
    @inv_collections[:computer_systems] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class => ComputerSystem,
        :parent      => ems,
        :association => :computer_systems,
        :manager_ref => [:managed_entity],
      ))
    @inv_collections[:computer_system_hardwares] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class => Hardware,
        :parent      => ems,
        :association => :computer_system_hardwares,
        :manager_ref => [:computer_system],
      ))
    @inv_collections[:computer_system_operating_systems] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class => OperatingSystem,
        :parent      => ems,
        :association => :computer_system_operating_systems,
        :manager_ref => [:computer_system],
      ))

    @inv_collections[:container_image_registries] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class    => ContainerImageRegistry,
        :parent         => ems,
        :builder_params => {:ems_id => ems.id},
        :association    => :container_image_registries,
        :manager_ref    => [:host, :port],
      ))
    @inv_collections[:container_images] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class    => ContainerImage,
        :parent         => ems,
        :builder_params => {:ems_id => ems.id},
        :association    => :container_images,
        # TODO: old save matches on [:image_ref, :container_image_registry_id]
        # TODO: should match on digest when available
        :manager_ref    => [:image_ref],
      ))
    initialize_custom_attributes_collections(ems.container_images, %w(labels docker_labels))

    @inv_collections[:container_groups] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class          => ContainerGroup,
        :parent               => ems,
        :builder_params       => {:ems_id => ems.id},
        :association          => :container_groups,
        :secondary_refs       => {:by_namespace_and_name => [:namespace, :name]},
        :attributes_blacklist => [:namespace],
      ))
    initialize_container_conditions_collection(ems.container_groups)
    initialize_custom_attributes_collections(ems.container_groups, %w(labels node_selectors))
    @inv_collections[:container_definitions] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class    => ContainerDefinition,
        :parent         => ems,
        :builder_params => {:ems_id => ems.id},
        :association    => :container_definitions,
        # parser sets :ems_ref => "#{pod_id}_#{container_def.name}_#{container_def.image}"
      ))
    @inv_collections[:container_volumes] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class => ContainerVolume,
        :parent      => ems,
        :association => :container_volumes,
        :manager_ref => [:parent, :name],
      ))
    @inv_collections[:containers] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class    => Container,
        :parent         => ems,
        :builder_params => {:ems_id => ems.id},
        :association    => :containers,
        # parser sets :ems_ref => "#{pod_id}_#{container.name}_#{container.image}"
      ))
    @inv_collections[:container_port_configs] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class => ContainerPortConfig,
        :parent      => ems,
        :association => :container_port_configs,
        # parser sets :ems_ref => "#{pod_id}_#{container_name}_#{port_config.containerPort}_#{port_config.hostPort}_#{port_config.protocol}"
      ))
    @inv_collections[:container_env_vars] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class => ContainerEnvVar,
        :parent      => ems,
        :association => :container_env_vars,
        # TODO: old save matches on all :name, :value, :field_path - does this matter?
        :manager_ref => [:container_definition, :name],
      ))
    @inv_collections[:security_contexts] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class => SecurityContext,
        :parent      => ems,
        :association => :security_contexts,
        :manager_ref => [:resource],
      ))

    @inv_collections[:container_replicators] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class          => ContainerReplicator,
        :parent               => ems,
        :builder_params       => {:ems_id => ems.id},
        :association          => :container_replicators,
        :secondary_refs       => {:by_namespace_and_name => [:namespace, :name]},
        :attributes_blacklist => [:namespace],
      ))
    initialize_custom_attributes_collections(ems.container_replicators, %w(labels selectors))

    @inv_collections[:container_services] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class          => ContainerService,
        :parent               => ems,
        :builder_params       => {:ems_id => ems.id},
        :association          => :container_services,
        :secondary_refs       => {:by_namespace_and_name => [:namespace, :name]},
        :attributes_blacklist => [:namespace],
      ))
    initialize_custom_attributes_collections(ems.container_services, %w(labels selectors))
    @inv_collections[:container_service_port_configs] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class => ContainerServicePortConfig,
        :parent      => ems,
        :association => :container_service_port_configs,
      ))

    @inv_collections[:container_routes] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class          => ContainerRoute,
        :parent               => ems,
        :builder_params       => {:ems_id => ems.id},
        :association          => :container_routes,
        :attributes_blacklist => [:namespace],
      ))
    initialize_custom_attributes_collections(ems.container_routes, %w(labels))

    @inv_collections[:container_component_statuses] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class    => ContainerComponentStatus,
        :parent         => ems,
        :builder_params => {:ems_id => ems.id},
        :association    => :container_component_statuses,
        :manager_ref    => [:name],
      ))

    @inv_collections[:container_templates] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class          => ContainerTemplate,
        :parent               => ems,
        :builder_params       => {:ems_id => ems.id},
        :association          => :container_templates,
        :attributes_blacklist => [:namespace],
      )
    initialize_custom_attributes_collections(ems.container_templates, %w(labels))
    @inv_collections[:container_template_parameters] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class => ContainerTemplateParameter,
        :parent      => ems,
        :association => :container_template_parameters,
        :manager_ref => [:container_template, :name],
      ))

    @inv_collections[:container_builds] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class    => ContainerBuild,
        :parent         => ems,
        :builder_params => {:ems_id => ems.id},
        :association    => :container_builds,
        :secondary_refs => {:by_namespace_and_name => [:namespace, :name]},
      ))
    initialize_custom_attributes_collections(ems.container_builds, %w(labels))
    @inv_collections[:container_build_pods] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class    => ContainerBuildPod,
        :parent         => ems,
        :builder_params => {:ems_id => ems.id},
        :association    => :container_build_pods,
        # TODO: convert namespace column -> container_project_id?
        :manager_ref    => [:namespace, :name],
        :secondary_refs => {:by_namespace_and_name => [:namespace, :name]},
      ))
    initialize_custom_attributes_collections(ems.container_build_pods, %w(labels))

    @inv_collections[:persistent_volumes] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class    => PersistentVolume,
        :parent         => ems,
        :builder_params => {:parent => ems},
        :association    => :persistent_volumes,
      ))
    @inv_collections[:persistent_volume_claims] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class    => PersistentVolumeClaim,
        :parent         => ems,
        :builder_params => {:ems_id => ems.id},
        :association    => :persistent_volume_claims,
      ))
  end

  # ContainerCondition is polymorphic child of ContainerNode & ContainerGroup.
  def initialize_container_conditions_collection(relation)
    query = ContainerCondition.where(
      :container_entity_type => relation.model.name,
      :container_entity_id   => relation, # nested SELECT. TODO: compare to a JOIN.
    )
    @inv_collections[[:container_conditions_for, relation.model.name]] =
      ::ManagerRefresh::InventoryCollection.new(shared_options.merge(
        :model_class => ContainerCondition,
        :arel        => query,
        :manager_ref => [:container_entity, :name],
      ))
  end

  # CustomAttribute is polymorphic child of many models
  def initialize_custom_attributes_collections(relation, sections)
    sections.each do |section|
      query = CustomAttribute.where(:resource_type => relation.model.name,
                                    :resource_id   => relation,
                                    :section       => section.to_s)
      @inv_collections[[:custom_attributes_for, relation.model.name, section]] = ::ManagerRefresh::InventoryCollection.new(
        shared_options.merge(
          :model_class => CustomAttribute,
          :arel        => query,
          :manager_ref => [:resource, :section, :name],
        )
      )
    end
  end
end
