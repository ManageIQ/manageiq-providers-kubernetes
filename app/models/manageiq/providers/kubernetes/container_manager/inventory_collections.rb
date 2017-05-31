module ManageIQ::Providers::Kubernetes::ContainerManager::InventoryCollections
  def initialize_inventory_collections(ems)
    # TODO: Targeted refreshes will require adjusting the associations / arels. (duh)
    @inv_collections = {}
    @inv_collections[:container_projects] = ::ManagerRefresh::InventoryCollection.new(
      :model_class => ContainerProject,
      :parent => ems,
      :builder_params => {:ems_id => ems.id},
      :association => :container_projects
    )
    @inv_collections[:container_quotas] = ::ManagerRefresh::InventoryCollection.new(
      :model_class => ContainerQuota,
      :parent => ems,
      :builder_params => {:ems_id => ems.id},
      :association => :container_quotas,
      #:arel => ContainerQuota.joins(:container_project).where(:container_projects => {:ems_id => ems.id}),
    )
    @inv_collections[:container_quota_items] = ::ManagerRefresh::InventoryCollection.new(
      :model_class => ContainerQuotaItem,
      :parent => ems,
      :association => :container_quota_items,
      #:arel => ContainerQuotaItem.joins(:container_quota => :container_project).where(:container_projects => {:ems_id => ems.id}),
      :manager_ref => [:container_quota, :resource],
    )
    @inv_collections[:container_limits] = ::ManagerRefresh::InventoryCollection.new(
      :model_class => ContainerLimit,
      :parent => ems,
      :builder_params => {:ems_id => ems.id},
      :association => :container_limits,
    )
    @inv_collections[:container_limit_items] = ::ManagerRefresh::InventoryCollection.new(
      :model_class => ContainerLimitItem,
      :parent => ems,
      :association => :container_limit_items,
      :manager_ref => [:container_limit, :resource, :item_type],
    )
    @inv_collections[:container_nodes] = ::ManagerRefresh::InventoryCollection.new(
      :model_class => ContainerNode,
      :parent => ems,
      :builder_params => {:ems_id => ems.id},
      :association => :container_nodes,
    )

    # polymorphic child of ContainerNode & ContainerImage,
    # but refresh only sets it on nodes.
    @inv_collections[:container_node_computer_systems] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => ComputerSystem,
        :parent => ems,
        :association => :container_node_computer_systems,
        :manager_ref => [:managed_entity],
      )
    @inv_collections[:container_node_computer_system_hardwares] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => Hardware,
        :parent => ems,
        :association => :container_node_computer_system_hardwares,
        :manager_ref => [:computer_system],
      )
    @inv_collections[:container_node_computer_system_operating_systems] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => OperatingSystem,
        :parent => ems,
        :association => :container_node_computer_system_operating_systems,
        :manager_ref => [:computer_system],
      )

    @inv_collections[:container_image_registries] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => ContainerImageRegistry,
        :parent => ems,
        :builder_params => {:ems_id => ems.id},
        :association => :container_image_registries,
        :manager_ref => [:host, :port],
      )
    @inv_collections[:container_images] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => ContainerImage,
        :parent => ems,
        :builder_params => {:ems_id => ems.id},
        :association => :container_images,
        :manager_ref => [:image_ref, :container_image_registry],
      )

    @inv_collections[:container_groups] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => ContainerGroup,
        :parent => ems,
        :builder_params => {:ems_id => ems.id},
        :association => :container_groups,
      )
    @inv_collections[:container_definitions] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => ContainerDefinition,
        :parent => ems,
        :builder_params => {:ems_id => ems.id},
        :association => :container_definitions,
        # parser sets :ems_ref => "#{pod_id}_#{container_def.name}_#{container_def.image}"
      )
    @inv_collections[:container_volumes] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => ContainerVolume,
        :parent => ems,
        :association => :container_volumes,
        :manager_ref => [:parent, :name],
      )
    @inv_collections[:containers] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => Container,
        :parent => ems,
        :builder_params => {:ems_id => ems.id},
        :association => :containers,
        # parser sets :ems_ref => "#{pod_id}_#{container.name}_#{container.image}"
      )
    @inv_collections[:container_port_configs] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => ContainerPortConfig,
        :parent => ems,
        :association => :container_port_configs,
        # parser sets :ems_ref => "#{pod_id}_#{container_name}_#{port_config.containerPort}_#{port_config.hostPort}_#{port_config.protocol}"
      )
    @inv_collections[:container_env_vars] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => ContainerEnvVar,
        :parent => ems,
        :association => :container_env_vars,
        # TODO: old save matches on all :name, :value, :field_path - does this matter?
        :manager_ref => [:container_definition, :name],
      )
    @inv_collections[:security_contexts] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => SecurityContext,
        :parent => ems,
        :association => :security_contexts,
        :manager_ref => [:resource],
      )

    @inv_collections[:container_replicators] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => ContainerReplicator,
        :parent => ems,
        :builder_params => {:ems_id => ems.id},
        :association => :container_replicators,
      )
    @inv_collections[:container_services] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => ContainerService,
        :parent => ems,
        :builder_params => {:ems_id => ems.id},
        :association => :container_services,
      )
    @inv_collections[:container_service_port_configs] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => ContainerServicePortConfig,
        :parent => ems,
        :association => :container_service_port_configs,
      )
    @inv_collections[:container_routes] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => ContainerRoute,
        :parent => ems,
        :builder_params => {:ems_id => ems.id},
        :association => :container_routes,
      )
    @inv_collections[:container_component_statuses] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => ContainerComponentStatus,
        :parent => ems,
        :builder_params => {:ems_id => ems.id},
        :association => :container_component_statuses,
        :manager_ref => [:name],
      )
    @inv_collections[:container_templates] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => ContainerTemplate,
        :parent => ems,
        :builder_params => {:ems_id => ems.id},
        :association => :container_templates,
      )
    @inv_collections[:container_template_parameters] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => ContainerTemplateParameter,
        :parent => ems,
        :association => :container_template_parameters,
        :manager_ref => [:container_template, :name],
      )
    @inv_collections[:container_builds] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => ContainerBuild,
        :parent => ems,
        :builder_params => {:ems_id => ems.id},
        :association => :container_builds,
      )
    @inv_collections[:container_build_pods] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => ContainerBuildPod,
        :parent => ems,
        :builder_params => {:ems_id => ems.id},
        :association => :container_build_pods,
        # TODO is this unique?  build pods do have uid that becomes ems_ref,
        # but we need lazy_find by name for lookup from container_group
        # TODO rename namespace -> container_project column?
        :manager_ref => [:namespace, :name],
      )
    @inv_collections[:persistent_volumes] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => PersistentVolume,
        :parent => ems,
        :builder_params => {:parent => ems},
        :association => :persistent_volumes,
      )
    @inv_collections[:persistent_volume_claims] =
      ::ManagerRefresh::InventoryCollection.new(
        :model_class => PersistentVolumeClaim,
        :parent => ems,
        :builder_params => {:ems_id => ems.id},
        :association => :persistent_volume_claims,
      )
  end
end
