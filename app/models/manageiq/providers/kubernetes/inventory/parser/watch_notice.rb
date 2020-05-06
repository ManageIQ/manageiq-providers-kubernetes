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

      collection_name = resource_by_entity(kind.underscore)
      next if collection_name.nil?

      manager_ref = send("parse_#{kind.underscore}_manager_ref", object)
      next if manager_ref.nil?

      inventory_collection = persister.send(resource_by_entity(kind.underscore).tableize)
      inventory_collection.targeted_scope << manager_ref
    end
  end
end
