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

        KUBERNETES_ENTITIES = [
          {:name => 'pods'}, {:name => 'services'}, {:name => 'replication_controllers'}, {:name => 'nodes'},
          {:name => 'endpoints'}, {:name => 'namespaces'}, {:name => 'resource_quotas'}, {:name => 'limit_ranges'},
          {:name => 'persistent_volumes'}, {:name => 'persistent_volume_claims'}
        ]

        def fetch_entities(client, entities)
          entities.each_with_object({}) do |entity, h|
            continue = nil
            h[entity[:name].singularize] ||= []

            begin
              loop do
                entities = client.send("get_#{entity[:name]}", :limit => refresher_options.chunk_size, :continue => continue)

                h[entity[:name].singularize].concat(entities)
                break if entities.last?

                continue = entities.continue
              end
            rescue KubeException => e
              raise e if entity[:default].nil?
              $log.warn("Unexpected Exception during refresh: #{e}")
              h[entity[:name].singularize] = entity[:default]
            end
          end
        end

        def manager_refresh_post_processing(_ems, _target, persister)
          raise_creation_events(persister.container_images)
          raise_creation_events(persister.container_projects)
        end

        def raise_creation_events(saved_collection)
          # We want this post processing job only for batches, for the rest it's after_create hook on the Model
          return unless saved_collection.saver_strategy == :batch

          # TODO extract the batch size to Settings
          batch_size = 100
          saved_collection.created_records.each_slice(batch_size) do |batch|
            collection_ids = batch.collect { |x| x[:id] }
            MiqQueue.submit_job(
              :class_name  => saved_collection.model_class.to_s,
              :method_name => 'raise_creation_events',
              :args        => [collection_ids],
              :priority    => MiqQueue::HIGH_PRIORITY
            )
          end
        end
      end
    end
  end
end
