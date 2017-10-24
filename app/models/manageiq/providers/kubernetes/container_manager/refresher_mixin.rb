module ManageIQ
  module Providers
    module Kubernetes
      module ContainerManager::RefresherMixin
        KUBERNETES_ENTITIES = [
          {:name => 'pods'}, {:name => 'services'}, {:name => 'replication_controllers'}, {:name => 'nodes'},
          {:name => 'endpoints'}, {:name => 'namespaces'}, {:name => 'resource_quotas'}, {:name => 'limit_ranges'},
          {:name => 'persistent_volumes'}, {:name => 'persistent_volume_claims'}
        ]

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

        def manager_refresh_post_processing(_ems, _target, persister)
          container_images_post_processing(persister.container_images)
        end

        def container_images_post_processing(container_images)
          # We want this post processing job only for batches, for the rest it's after_create hook on the Model
          return unless container_images.saver_strategy == :batch

          # TODO extract the batch size to Settings
          batch_size = 100
          container_images.created_records.each_slice(batch_size) do |batch|
            container_images_ids = batch.collect { |x| x[:id] }
            MiqQueue.submit_job(
              :class_name  => "ContainerImage",
              :method_name => 'raise_creation_events',
              :args        => [container_images_ids],
              :priority    => MiqQueue::HIGH_PRIORITY
            )
          end
        end
      end
    end
  end
end
