module ManageIQ::Providers::Kubernetes::ContainerManager::ContainerGroup::Logs
  def logs(container_name, options = {})
    params = {:container => container_name}.merge(options)

    ext_management_system
      .connect(:service => "kubernetes")
      .get_pod_log(
        name,
        container_project.name,
        **params
      )
      .body
  end
end
