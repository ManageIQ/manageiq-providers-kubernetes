class ManageIQ::Providers::Kubernetes::Inventory::Collector < ManageIQ::Providers::Inventory::Collector
  require_nested :TargetCollection
  require_nested :Watches
end
