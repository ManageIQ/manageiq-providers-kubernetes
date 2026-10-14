module ManageIQ::Providers::Kubernetes::ContainerManager::ContainerGroup::Logs
  SUPPORTED_LOG_OPTIONS = %i[container container_name tail_lines timestamps since_seconds since_time previous limit_bytes].freeze

  def raw_logs(options = {})
    opts = options.symbolize_keys.slice(*SUPPORTED_LOG_OPTIONS)
    opts[:container] ||= opts.delete(:container_name) || containers.first&.name

    ext_management_system
      .connect(:service => "kubernetes")
      .get_pod_log(name, container_project.name, **opts)
      .body
  end
end
