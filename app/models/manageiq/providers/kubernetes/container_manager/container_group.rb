class ManageIQ::Providers::Kubernetes::ContainerManager::ContainerGroup < ContainerGroup
  include Logs
  include RemoteConsole

  alias_attribute :pod_uid, :ems_ref

  supports :capture
  supports :logs do
    if ext_management_system.nil?
      _("The Pod is not associated with an active provider")
    elsif container_project.nil?
      _("The Pod is not associated with a project")
    end
  end

  def self.display_name(number = 1)
    n_('Pod (Kubernetes)', 'Pods (Kubernetes)', number)
  end
end
