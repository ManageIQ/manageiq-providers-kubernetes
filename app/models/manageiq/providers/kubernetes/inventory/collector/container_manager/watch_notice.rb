class ManageIQ::Providers::Kubernetes::Inventory::Collector::ContainerManager::WatchNotice < ManageIQ::Providers::Kubernetes::Inventory::Collector
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
    unless @endpoints_collected
      @endpoints += get_missing("endpoints")
      @endpoints_collected = true
    end

    @endpoints
  end

  def services
    unless @services_collected
      @services += get_missing("services")
      @services_collected = true
    end

    @services
  end

  private

  def initialize_collections!
    @additional_attributes    = {}
    @pods                     = []
    @services                 = []
    @endpoints                = []
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

  def get_missing(kind)
    get_collection(kind.singularize, send("missing_#{kind}"))
  end

  def missing_endpoints
    service_targets - endpoint_targets
  end

  def missing_services
    endpoint_targets - service_targets
  end

  def service_targets
    @services.map { |svc| name_and_namespace(svc) }.compact
  end

  def endpoint_targets
    @endpoints.map { |ep| name_and_namespace(ep) }.compact
  end

  def name_and_namespace(obj)
    obj&.metadata&.to_h&.values_at(:name, :namespace)&.compact
  end

  def get_collection(kind, objects_to_collect)
    objects_to_collect.map { |name, namespace| safe_get(kind, name, namespace) }.compact
  end

  def safe_get(kind, name, namespace)
    kubernetes_connection.send("get_#{kind}", name, namespace)
  rescue Kubeclient::ResourceNotFoundError
    nil
  end
end
