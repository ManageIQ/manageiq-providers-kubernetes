module ManageIQ::Providers::Kubernetes
  class ContainerManager::Refresher < ManageIQ::Providers::BaseManager::Refresher
    include ::EmsRefresh::Refreshers::EmsRefresherMixin
    include ManageIQ::Providers::Kubernetes::ContainerManager::RefresherMixin

    def target_collection_collector_class
      ManageIQ::Providers::Kubernetes::Inventory::Collector::TargetCollection
    end

    def refresh_parser_class
      ManageIQ::Providers::Kubernetes::ContainerManager::RefreshParser
    end

    def all_entities
      KUBERNETES_ENTITIES
    end

    def collect_full_inventory(ems)
      ems.with_provider_connection { |client| fetch_entities(client, KUBERNETES_ENTITIES) }
    end
  end
end
