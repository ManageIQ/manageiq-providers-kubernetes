class ManageIQ::Providers::Kubernetes::ContainerManager::ContainerGroup < ::ContainerGroup
  include ActsAsStiLeafClass

  alias_attribute :pod_uid, :ems_ref

  def self.display_name(number = 1)
    n_('Pod (Kubernetes)', 'Pods (Kubernetes)', number)
  end
end
