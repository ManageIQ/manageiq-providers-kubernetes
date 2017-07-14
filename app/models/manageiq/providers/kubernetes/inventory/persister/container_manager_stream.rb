class ManageIQ::Providers::Kubernetes::Inventory::Persister::ContainerManagerStream <
  ManageIQ::Providers::Kubernetes::Inventory::Persister::ContainerManager

  def targeted
    true
  end

  def strategy
    :local_db_find_missing_references
  end

  def saver_strategy
    # :concurrent_safe
    # :default
    :concurrent_safe_batch
  end
end
