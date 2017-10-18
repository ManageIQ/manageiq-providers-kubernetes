class ManageIQ::Providers::Kubernetes::Inventory::Collector < ManagerRefresh::Inventory::Collector
  require_nested :TargetCollection
end
