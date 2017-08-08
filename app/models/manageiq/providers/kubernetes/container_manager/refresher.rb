module ManageIQ::Providers::Kubernetes
  class ContainerManager::Refresher < ManageIQ::Providers::BaseManager::Refresher
    include ::EmsRefresh::Refreshers::EmsRefresherMixin
    include ManageIQ::Providers::Kubernetes::ContainerManager::RefresherMixin

    # Full refresh. Collecting immediately. Don't have separate Collector classes.
    def collect_inventory_for_targets(ems, _targets)
      inventory = ems.with_provider_connection { |client| fetch_entities(client, KUBERNETES_ENTITIES) }
      EmsRefresh.log_inv_debug_trace(inventory, "inv_hash:")
      [[ems, inventory]]
    end

    def parse_targeted_inventory(ems, _target_is_ems, inventory)
      if refresher_options.inventory_object_refresh
        ManageIQ::Providers::Kubernetes::ContainerManager::RefreshParser.ems_inv_to_inv_collections(ems, inventory, refresher_options)
      else
        ManageIQ::Providers::Kubernetes::ContainerManager::RefreshParser.ems_inv_to_hashes(inventory, refresher_options)
      end
    end
  end
end
