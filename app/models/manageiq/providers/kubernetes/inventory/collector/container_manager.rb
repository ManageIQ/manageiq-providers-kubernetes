class ManageIQ::Providers::Kubernetes::Inventory::Collector::ContainerManager < ManageIQ::Providers::Kubernetes::Inventory::Collector
  attr_reader :inventory

  def collect
    @inventory = fetch_entities(kubernetes_connection, kubernetes_entities)
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

  def kubernetes_entities
    %w[pods services replication_controllers nodes endpoints namespaces resource_quotas limit_ranges persistent_volumes persistent_volume_claims]
  end

  def fetch_entities(client, entities)
    entities.each_with_object({}) do |entity, h|
      continue = nil
      h[entity.singularize] ||= []

      loop do
        entities = client.send("get_#{entity}", :limit => refresher_options.chunk_size, :continue => continue)

        h[entity.singularize].concat(entities)
        break if entities.last?

        continue = entities.continue
      end
    end
  end
end
