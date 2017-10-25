class ManageIQ::Providers::Kubernetes::Inventory::Persister::TargetCollection < ManageIQ::Providers::Kubernetes::Inventory::Persister::ContainerManager
  def targeted
    false # TODO(lsmola) get ready for true, which means a proper targeted refresh. That will require more effort.
  end

  def strategy
    nil
  end

  def shared_options
    settings_options = options[:inventory_collections].try(:to_hash) || {}

    settings_options.merge(
      :targeted => targeted,
      :complete => false, # For now, we want to a only create and update elements using watches data, delete events could
      # probably set finished_at and deleted_on dates, as an update based disconnect_inv.
      :strategy => :local_db_find_missing_references, # By default no IC will be saved
    )
  end
end
