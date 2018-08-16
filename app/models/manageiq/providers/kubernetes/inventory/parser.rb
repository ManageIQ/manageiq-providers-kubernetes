class ManageIQ::Providers::Kubernetes::Inventory::Parser < ManagerRefresh::Inventory::Parser
  require_nested :ContainerManager
end
