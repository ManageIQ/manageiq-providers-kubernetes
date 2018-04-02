module ManageIQ::Providers::Kubernetes::ContainerManager::TargetCollectionMixin
  def inventory(entities)
    full_inventory = empty_inventory(entities)

    # Fill pods from Targets
    pods                  = pod_list
    full_inventory['pod'] = pods
    # Fill pods references
    full_inventory.merge!(pods_references(pods))

    full_inventory
  end

  def empty_inventory(entities)
    # Return [] for all entities by default
    entities.each_with_object({}) { |entity, obj| obj[entity[:name].singularize] = [] }
  end

  def pods_references(pods)
    references = {}

    # Get references to Nodes and Projects(namespaces)
    node_names    = pods.map { |pod| pod.spec.nodeName }.uniq.compact
    project_names = pods.map { |pod| pod.metadata.namespace }.uniq.compact
    # TODO(lsmola) filter the references and get back only those that are not in our DB. This needs DB strategy for the
    # secondary indexes first.

    # Threshold for determining if it's better to fetch all entities, rather than doing individual API query for each
    threshold = options.api_filter_vs_full_list_threshold || 40

    manager.with_provider_connection(:service => ManageIQ::Providers::Kubernetes::ContainerManager.ems_type) do |client|
      # Fetch all nodes and projects, so we can always connect pods to them
      references['node']      = filter_or_fetch_all(threshold, client, node_names, 'nodes')
      references['namespace'] = filter_or_fetch_all(threshold, client, project_names, 'namespaces')
    end
    references
  end

  def pod_list
    targets = target.targets.map { |target| JSON.parse(target.options[:payload], :object_class => OpenStruct) }
    # Return only the latest occurrence of each pod
    targets.index_by { |x| x.metadata.uid }.values
  end

  private

  def filter_or_fetch_all(threshold, client, names, entity_name)
    if names.count > threshold
      client.send("get_#{entity_name}")
    else
      names.map { |name| client.send("get_#{entity_name.singularize}", name) }
    end
  end
end
