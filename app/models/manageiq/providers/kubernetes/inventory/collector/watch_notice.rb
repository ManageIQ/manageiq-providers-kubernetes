class ManageIQ::Providers::Kubernetes::Inventory::Collector::WatchNotice < ManageIQ::Providers::Kubernetes::Inventory::Collector
  attr_reader :additional_attributes, :pods, :services, :replication_controllers,
              :namespaces, :nodes, :notices, :resource_quotas, :limit_ranges,
              :persistent_volumes, :persistent_volume_claims

  def initialize(manager, notices)
    @notices = filter_notices(notices)

    initialize_collections!
    populate_collections!

    super(manager, nil)
  end

  def endpoints
    @endpoints ||= begin
      services.each_with_object([]) do |service, results|
        begin
          endpoint = kubernetes_connection.get_endpoint(service.metadata.name, service.metadata.namespace)
          results << endpoint
        rescue Kubeclient::ResourceNotFoundError
        end
      end
    end
  end

  private

  def initialize_collections!
    @additional_attributes    = {}
    @pods                     = []
    @services                 = []
    @replication_controllers  = []
    @nodes                    = []
    @namespaces               = []
    @resource_quotas          = []
    @limit_ranges             = []
    @persistent_volumes       = []
    @persistent_volume_claims = []
  end

  # The notices returned by the Kubernetes API contain always the complete
  # representation of the object, so it isn't necessary to process all of them,
  # only the last one for each object.
  def filter_notices(all_notices)
    notices_by_kind = all_notices.group_by { |notice| notice.object&.kind }.except(nil)

    notices_by_kind.values.each_with_object([]) do |notices, result|
      notices.reverse!.uniq! { |n| n.object&.metadata&.uid }
      result.concat(notices)
    end
  end

  # Pull the object out of the notices and populate the normal collections
  # so that the Parser::ContainerManager can be used normally
  def populate_collections!
    # Only add ADDED/MODIFIED to the collectors so deleted objects will be removed
    notices.reject { |n| n.type == "DELETED" }.each do |notice|
      instance_variable_get("@#{notice.object.kind.tableize}") << notice.object
    end
  end
end
