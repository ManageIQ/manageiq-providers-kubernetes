module ManageIQ::Providers::Kubernetes::ContainerManager::ContainerGroup::Logs
  SUPPORTED_LOG_OPTIONS = %i[container container_name tail_lines timestamps since_seconds since_time previous limit_bytes].freeze

  def logs_queue(userid, options = {})
    raise MiqException::Error, unsupported_reason(:logs) unless supports?(:logs)

    task_opts = {
      :action => "Fetching logs for Pod #{name}",
      :userid => userid
    }

    queue_opts = {
      :class_name  => self.class.name,
      :instance_id => id,
      :method_name => "raw_logs",
      :args        => [sanitize_log_options(options)],
      :role        => "ems_operations",
      :zone        => my_zone,
      :queue_name  => ext_management_system.queue_name_for_ems_operations
    }

    MiqTask.generic_action_with_callback(task_opts, queue_opts)
  end

  def raw_logs(options = {})
    opts = sanitize_log_options(options)
    opts[:container] ||= opts.delete(:container_name) || containers.first&.name

    ext_management_system
      .connect(:service => "kubernetes")
      .get_pod_log(name, container_project.name, **opts)
      .body
  end

  private

  def sanitize_log_options(options)
    options.symbolize_keys.slice(*SUPPORTED_LOG_OPTIONS)
  end
end
