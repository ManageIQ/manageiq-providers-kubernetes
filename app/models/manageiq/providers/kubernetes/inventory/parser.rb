class ManageIQ::Providers::Kubernetes::Inventory::Parser < ManageIQ::Providers::Inventory::Parser
  require_nested :ContainerManager
end
