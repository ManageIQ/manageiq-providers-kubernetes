autoload(:KubeException, 'kubeclient')

module ManageIQ
  module Providers
    module Kubernetes
      module ContainerManager::RefresherMixin
        def collect_inventory_for_targets(ems, targets)
          # TODO(lsmola) we need to move to common Graph Refresh architecture with Inventory Builder having Collector,
          # Parser and Persister
          targets.map do |target|
            inventory = collect_full_inventory(ems)
            EmsRefresh.log_inv_debug_trace(inventory, "inv_hash:")
            [target, inventory]
          end
        end

        def parse_targeted_inventory(ems, target, inventory)
          refresh_parser_class.ems_inv_to_persister(ems, inventory, refresher_options)
        end

        KUBERNETES_ENTITIES = %w[pods services replication_controllers nodes endpoints namespaces resource_quotas limit_ranges persistent_volumes persistent_volume_claims]

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
    end
  end
end
