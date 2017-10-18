class ManageIQ::Providers::Kubernetes::Inventory::Persister < ManagerRefresh::Inventory::Persister
  require_nested :ContainerManager
  require_nested :TargetCollection
end
