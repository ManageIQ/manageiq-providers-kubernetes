class ManageIQ::Providers::Kubernetes::Inventory::Parser < ManageIQ::Providers::Inventory::Parser
  require_nested :ContainerManager

  def refresher_options
    Settings.ems_refresh[collector.manager.class.ems_type]
  end
end
