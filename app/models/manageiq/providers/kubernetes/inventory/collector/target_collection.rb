class ManageIQ::Providers::Kubernetes::Inventory::Collector::TargetCollection < ManageIQ::Providers::Kubernetes::Inventory::Collector
  def inventory(entities)
    # Return [] for all inventory call by default
    full_inventory = entities.each_with_object({}) { |entity, obj| obj[entity[:name].singularize] = [] }

    # Fill pods from Targets
    full_inventory['pod'] = pods

    # TODO(lsmola) we should either have watches for nodes and projects + db load strategy based on names, oR we should
    # fetch only referenced nodes and projects from the API
    # Fetch all nodes and projects, so we can always connect pods to them
    kube_inventory = manager.with_provider_connection(:service => ManageIQ::Providers::Kubernetes::ContainerManager.ems_type) do |kubeclient|
      fetch_entities(kubeclient, [{:name => 'nodes'}, {:name => 'namespaces'}])
    end

    full_inventory['node']      = kube_inventory['node']
    full_inventory['namespace'] = kube_inventory['namespace']

    full_inventory
  end

  def pods
    # We have only pods targets now
    target.targets.map { |target| JSON.parse(target.options, object_class: OpenStruct).payload }
  end

  private

  # TODO(lsmola) this method comes from the refresher, expose it somewhere where we can share it, but more likely we
  # be fetching subsets of entities, so this will look different
  def fetch_entities(client, entities)
    entities.each_with_object({}) do |entity, h|
      begin
        h[entity[:name].singularize] = client.send("get_#{entity[:name]}")
      rescue KubeException => e
        raise e if entity[:default].nil?
        $log.warn("Unexpected Exception during refresh: #{e}")
        h[entity[:name].singularize] = entity[:default]
      end
    end
  end
end
