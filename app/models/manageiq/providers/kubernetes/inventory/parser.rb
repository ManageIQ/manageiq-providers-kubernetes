class ManageIQ::Providers::Kubernetes::Inventory::Parser < ManageIQ::Providers::Inventory::Parser
  require_nested :ContainerManager

  def refresher_options
    Settings.ems_refresh[persister.manager.class.ems_type]
  end
end
