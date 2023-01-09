class ManageIQ::Providers::Kubernetes::ContainerManager::ContainerGroup < ::ContainerGroup
  alias_attribute :pod_uid, :ems_ref

  supports :capture

  def self.display_name(number = 1)
    n_('Pod (Kubernetes)', 'Pods (Kubernetes)', number)
  end
end
