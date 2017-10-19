module ManageIQ::Providers::Kubernetes::ContainerManager::TargetCollectionMixin
  def inventory(entities)
    full_inventory = clean_inventory(entities)

    # Fill pods from Targets
    full_inventory['pod'] = pods
    # Fill pods references
    full_inventory.merge!(pods_references(pods))

    full_inventory
  end

  def clean_inventory(entities)
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
      references['node']      = if node_names.count > threshold
                                  fetch_entity(client, 'nodes')
                                else
                                  node_names.map { |name| fetch_entity(client, 'node', name) }
                                end
      references['namespace'] = if project_names.count > threshold
                                  fetch_entity(client, 'namespaces')
                                else
                                  project_names.map { |name| fetch_entity(client, 'namespace', name) }
                                end
    end
    references
  end

  def pods
    target.targets.map { |target| JSON.parse(target.options, :object_class => OpenStruct).payload }
  end

  private

  def fetch_entity(client, entity_name, filter = nil)
    if filter
      client.send("get_#{entity_name}", filter)
    else
      client.send("get_#{entity_name}")
    end
  end
end
