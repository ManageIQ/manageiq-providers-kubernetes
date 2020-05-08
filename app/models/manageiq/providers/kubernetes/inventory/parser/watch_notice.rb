class ManageIQ::Providers::Kubernetes::Inventory::Parser::WatchNotice < ManageIQ::Providers::Kubernetes::Inventory::Parser::ContainerManager
  def parse
    parse_notices

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

  def parse_notices
    collector.notices.each do |notice|
      object = notice.object
      kind   = object.kind

      inventory_collection = persister.send(resource_by_entity(kind.underscore).tableize)
      inventory_collection.targeted_scope << object.metadata.uid
    end
  end

  def cgs_by_namespace_and_name
    nil
  end
end
