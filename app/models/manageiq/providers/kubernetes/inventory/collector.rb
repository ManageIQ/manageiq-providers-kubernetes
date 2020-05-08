class ManageIQ::Providers::Kubernetes::Inventory::Collector < ManageIQ::Providers::Inventory::Collector
  require_nested :ContainerManager
  require_nested :WatchNotice
end
