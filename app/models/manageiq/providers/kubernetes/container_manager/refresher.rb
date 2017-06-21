module ManageIQ::Providers::Kubernetes
  class ContainerManager::Refresher < ManageIQ::Providers::BaseManager::Refresher
    include ::EmsRefresh::Refreshers::EmsRefresherMixin
    include ManageIQ::Providers::Kubernetes::ContainerManager::RefresherMixin

    def parse_legacy_inventory(ems)
      entities = ems.with_provider_connection { |client| fetch_entities(client, KUBERNETES_ENTITIES) }
      EmsRefresh.log_inv_debug_trace(entities, "inv_hash:")

      if refresher_options.try(:[], :inventory_object_refresh)
        ManageIQ::Providers::Kubernetes::ContainerManager::RefreshParser.ems_inv_to_inv_collections(ems, entities, refresher_options)
      else
        ManageIQ::Providers::Kubernetes::ContainerManager::RefreshParser.ems_inv_to_hashes(entities, refresher_options)
      end
    end
  end
end
