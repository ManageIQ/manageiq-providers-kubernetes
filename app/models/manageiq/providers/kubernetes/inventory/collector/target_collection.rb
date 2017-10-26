class ManageIQ::Providers::Kubernetes::Inventory::Collector::TargetCollection < ManageIQ::Providers::Kubernetes::Inventory::Collector
  include ManageIQ::Providers::Kubernetes::ContainerManager::TargetCollectionMixin
end
