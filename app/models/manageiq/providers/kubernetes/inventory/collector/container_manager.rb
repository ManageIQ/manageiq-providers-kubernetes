class ManageIQ::Providers::Kubernetes::Inventory::Collector::ContainerManager < ManageIQ::Providers::Kubernetes::Inventory::Collector
  def additional_attributes
    @additional_attributes ||= {} # TODO is this used?
  end

  def pods
    @pods ||= fetch_entity(kubernetes_connection, "pods")
  end

  def services
    @services ||= fetch_entity(kubernetes_connection, "services")
  end

  def endpoints
    @endpoints ||= fetch_entity(kubernetes_connection, "endpoints")
  end

  def replication_controllers
    @replication_controllers ||= fetch_entity(kubernetes_connection, "replication_controllers")
  end

  def nodes
    @nodes ||= fetch_entity(kubernetes_connection, "nodes")
  end

  def namespaces
    @namespaces ||= fetch_entity(kubernetes_connection, "namespaces")
  end

  def resource_quotas
    @resource_quotas ||= fetch_entity(kubernetes_connection, "resource_quotas")
  end

  def limit_ranges
    @limit_ranges ||= fetch_entity(kubernetes_connection, "limit_ranges")
  end

  def persistent_volumes
    @persistent_volumes ||= fetch_entity(kubernetes_connection, "persistent_volumes")
  end

  def persistent_volume_claims
    @persistent_volume_claims ||= fetch_entity(kubernetes_connection, "persistent_volume_claims")
  end

  private

  def refresher_options
    Settings.ems_refresh[manager.class.ems_type]
  end

  def connect(service)
    manager.connect(:service => service)
  rescue KubeException
    nil
  end

  def kubernetes_connection
    @kubernetes_connection ||= connect("kubernetes")
  end

  def fetch_entity(client, entity)
    meth = "get_#{entity}"

    continue = nil
    results = []

    loop do
      result = client.send(meth, :limit => refresher_options.chunk_size, :continue => continue)
      results += result
      break if result.last?

      continue = result.continue
    end

    results
  end
end
