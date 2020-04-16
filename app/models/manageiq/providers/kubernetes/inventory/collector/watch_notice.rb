class ManageIQ::Providers::Kubernetes::Inventory::Collector::WatchNotice < ManageIQ::Providers::Kubernetes::Inventory::Collector
  attr_reader :additional_attributes, :pods, :services, :endpoints, :replication_controllers,
              :nodes, :namespaces, :resource_quotas, :limit_ranges, :persistent_volumes, :persistent_volume_claims

  def initialize(manager, notices)
    initialize_collections!
    parse_notices!(notices)

    super(manager, nil)
  end

  private

  def initialize_collections!
    @additional_attributes = {}
    @pods = []
    @services = []
    @endpoints = []
    @replication_controllers = []
    @nodes = []
    @namespaces = []
    @resource_quotas = []
    @limit_ranges = []
    @persistent_volumes = []
    @persistent_volume_claims = []
  end

  def parse_notices!(all_notices)
    notices_by_kind = all_notices.group_by { |notice| notice.object&.kind }.except(nil)
    notices_by_kind.each do |kind, notices|
      # The notices returned by the Kubernetes API contain always the complete representation of the object, so it isn't
      # necessary to process all of them, only the last one for each object.
      notices.reverse!.uniq! { |n| n.object&.metadata&.uid }

      # Only add ADDED/MODIFIED to the collectors so deleted objects will be removed
      instance_variable_get("@#{kind.tableize}")&.concat(notices)
    end
  end
end
