class ManageIQ::Providers::Kubernetes::Inventory::Collector::WatchNotice < ManageIQ::Providers::Kubernetes::Inventory::Collector
  attr_reader :additional_attributes, :pods, :replication_controllers,
              :namespaces, :nodes, :notices, :resource_quotas, :limit_ranges,
              :persistent_volumes, :persistent_volume_claims

  def initialize(manager, notices)
    @notices = filter_notices(notices)

    initialize_collections!
    populate_collections!

    super(manager, nil)
  end

  # Endpoints and services come from two different watches but are
  # merged into one model in manageiq.  This means we have to watch
  # for updates to both entity kinds and if we receive an update
  # we have to get the current state of the other one.
  #
  # If we get an endpoint notice we have to get the service with
  # the same name and namespace, and vice versa
  def endpoints
    return @endpoints if @endpoints_collected

    services = @services.map do |service|
      [service.metadata.name, service.metadata.namespace]
    end

    endpoints_to_collect = services - @endpoints.map { |ep| [ep.metadata.name, ep.metadata.namespace] }

    endpoints_to_collect.each do |name, namespace|
      @endpoints << kubernetes_connection.get_endpoint(name, namespace)
    rescue Kubeclient::ResourceNotFoundError
      nil
    end

    @endpoints_collected = true
    @endpoints
  end

  def services
    return @services if @services_collected

    endpoints = @endpoints.map do |endpoint|
      [endpoint.metadata.name, endpoint.metadata.namespace]
    end

    services_to_collect = endpoints - @services.map { |svc| [svc.metadata.name, svc.metadata.namespace] }

    services_to_collect.each do |name, namespace|
      @services << kubernetes_connection.get_service(name, namespace)
    rescue Kubeclient::ResourceNotFoundError
      nil
    end

    @services_collected = true
    @services
  end

  private

  def initialize_collections!
    @additional_attributes    = {}
    @pods                     = []
    @endpoints                = []
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
