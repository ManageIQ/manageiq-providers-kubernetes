class ManageIQ::Providers::Kubernetes::Inventory::Parser::WatchNotice < ManageIQ::Providers::Kubernetes::Inventory::Parser::ContainerManager
  def parse
    pods
    services
    replication_controllers
    nodes
    namespaces
    resource_quotas
    limit_ranges
    persistent_volumes
    persistent_volume_claims
  end

  def pods
    collector.pods.each do |notice|
      pod = notice.object

      persister.container_groups.targeted_scope << pod.metadata.uid
      next if notice.type == "DELETED"

      parse_pod(pod)
    end
  end

  def services
    collector.services.each do |notice|
      service = notice.object

      persister.container_services.targeted_scope << service.metadata.uid
      next if notice.type == "DELETED"

      parse_service(service)
    end
  end

  def replication_controllers
    collector.replication_controllers.each do |notice|
      replication_controller = notice.object

      persister.container_replicators.targeted_scope << replication_controller.metadata.uid
      next if notice.type == "DELETED"

      parse_replication_controller(replication_controller)
    end
  end

  def nodes
    collector.nodes.each do |notice|
      node = notice.object

      persister.container_nodes.targeted_scope << node.metadata.uid
      next if notice.type == "DELETED"

      parse_node(node)
    end
  end

  def namespaces
    collector.namespaces.each do |notice|
      namespace = notice.object

      persister.container_projects.targeted_scope << namespace.metadata.uid
      next if notice.type == "DELETED"

      parse_namespace(namespace)
    end
  end

  def resource_quotas
    collector.resource_quotas.each do |notice|
      quota = notice.object

      persister.container_quotas.targeted_scope << quota.metadata.uid
      next if notice.type == "DELETED"

      parse_resource_quota(quota)
    end
  end

  def limit_ranges
    collector.limit_ranges.each do |notice|
      limit_range = notice.object

      persister.container_limits.targeted_scope << limit_range.metadata.uid
      next if notice.type == "DELETED"

      parse_range(limit_range)
    end
  end

  def persistent_volumes
    collector.persistent_volumes.each do |notice|
      pv = notice.object

      persister.persistent_volumes.targeted_scope << pv.metadata.uid
      next if notice.type == "DELETED"

      parse_persistent_volume(pv)
    end
  end

  def persistent_volume_claims
    collector.persistent_volume_claims.each do |notice|
      pvc = notice.object

      persister.persistent_volume_claims.targeted_scope << pvc.metadata.uid
      next if notice.type == "DELETED"

      parse_persistent_volume_claim(pvc)
    end
  end
end
