module ManageIQ::Providers::Kubernetes::ContainerManager::EntitiesMapping
  # Update this mapping with any new containers entity added to manageiq
  MAPPING = {
    'node'                    => 'ContainerNode',
    'namespace'               => 'ContainerProject',
    'resource_quota'          => 'ContainerQuota',
    'limit_range'             => 'ContainerLimit',
    'replication_controller'  => 'ContainerReplicator',
    'persistent_volume_claim' => 'PersistentVolumeClaim',
    'persistent_volume'       => 'PersistentVolume',
    'pod'                     => 'ContainerGroup',
    'service'                 => 'ContainerService',
    'component_status'        => 'ContainerComponentStatus',
    'project'                 => 'ContainerProject',
    'route'                   => 'ContainerRoute',
    'build_config'            => 'ContainerBuild',
    'build'                   => 'ContainerBuildPod',
    'template'                => 'ContainerTemplate',
    'image'                   => 'ContainerImage'
  }.freeze

  def miq_entity(entity)
    MAPPING[entity]
  end
end
