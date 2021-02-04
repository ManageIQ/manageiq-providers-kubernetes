class ManageIQ::Providers::Kubernetes::Inventory::Persister < ManageIQ::Providers::Inventory::Persister
  require_nested :ContainerManager
end
