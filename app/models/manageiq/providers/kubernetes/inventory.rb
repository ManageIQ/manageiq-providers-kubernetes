class ManageIQ::Providers::Kubernetes::Inventory < ManagerRefresh::Inventory
  require_nested :Persister
end
