class ManageIQ::Providers::Kubernetes::Inventory::Collector::ContainerManager < ManageIQ::Providers::Kubernetes::Inventory::Collector
  # TODO(lsmola) we need to return iterator for each collection, so we avoid fetching too many items to memory at
  # once.
  # Hints from cben:
  # A slightly open question in kubeclient iterator interface was how it should expose whole-collection resource_version
  # (and other metadata). Should iterator yield it with every item, or return it at the end?
  # With streaming parse (abonas/kubeclient#254), this depends on order of json. k8s puts items last, so version is
  # known by time we start yielding; this is unlikely to change but I feel weird hardcoding this assumption...
  # For chunking (abonas/kubeclient#283), we'll have metadata in each chunk, so either API works. Chunking also brings
  # risk of getting 410 Gone if we wait too long, not sure how to handle that.

  def namespaces
    @namespaces ||= connection.get_namespaces
  end

  def pods
    @pods ||= connection.get_pods
  end

  def cluster_service_offerings
    @cluster_service_offerings ||= service_catalog_connection.get_cluster_service_classes
  end

  def cluster_service_parameters_sets
    @cluster_service_parameters_sets ||= service_catalog_connection.get_cluster_service_plans
  end

  def service_instances
    @service_instances ||= service_catalog_connection.get_service_instances
  end

  private

  def connection
    @connection ||= manager.connect(:service => "kubernetes")
  end

  def service_catalog_connection
    @service_catalog_connection ||= manager.connect(:service => "kubernetes_service_catalog")
  end
end
