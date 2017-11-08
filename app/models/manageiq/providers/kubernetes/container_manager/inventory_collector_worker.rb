class ManageIQ::Providers::Kubernetes::ContainerManager::InventoryCollectorWorker < ManageIQ::Providers::BaseManager::InventoryCollectorWorker
  require_nested :Runner

  def self.has_required_role?
    return false unless Settings.fetch_path(:ems_refresh, ems_class.ems_type.to_sym, :inventory_object_refresh)
    super
  end
end
