class ManageIQ::Providers::Kubernetes::ContainerManager::InventoryCollectorWorker < ManageIQ::Providers::BaseManager::InventoryCollectorWorker
  require_nested :Runner
end
