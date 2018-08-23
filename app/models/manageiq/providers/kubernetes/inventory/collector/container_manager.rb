class ManageIQ::Providers::Kubernetes::Inventory::Collector::ContainerManager < ManageIQ::Providers::Kubernetes::Inventory::Collector
  def namespaces
    entities_iterator(connection, :namespaces)
  end

  def pods
    entities_iterator(connection, :pods)
  end

  def cluster_service_classes
    entities_iterator(service_catalog_connection, :cluster_service_classes)
  end

  def cluster_service_plans
    entities_iterator(service_catalog_connection, :cluster_service_plans)
  end

  def service_instances
    entities_iterator(service_catalog_connection, :service_instances)
  end

  private

  def connection
    @connection ||= manager.connect(:service => "kubernetes")
  end

  def service_catalog_connection
    @service_catalog_connection ||= manager.connect(:service => "kubernetes_service_catalog")
  end

  def entities_iterator(client, entity)
    # TODO(lsmola) change to iterator, that will fetch paginated response from the server, never fetching everything
    # at once
    client.send("get_#{entity}")
  rescue KubeException => e
    # TODO(lsmola) the old refresh has entities that can throws error and return some :default set
    _log.error("Unexpected Exception during fetching of entity #{entity}: #{e}")
    _log.error(e.backtrace.join("\n"))
    []
  end
end
