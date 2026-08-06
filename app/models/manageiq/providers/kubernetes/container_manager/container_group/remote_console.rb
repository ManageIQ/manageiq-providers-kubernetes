module ManageIQ::Providers::Kubernetes::ContainerManager::ContainerGroup::RemoteConsole
  def console_supported?(type)
    %w[KUBE_EXEC].include?(type.upcase)
  end

  def validate_remote_console_acquire_ticket(protocol, _options = {})
    if ext_management_system.nil?
      raise MiqException::RemoteConsoleNotSupportedError,
        "#{protocol} remote console requires the pod to be registered with a management system."
    end

    unless phase == "Running"
      raise MiqException::RemoteConsoleNotSupportedError,
        "#{protocol} remote console requires the pod to be running."
    end
  end

  def remote_console_acquire_ticket(userid, originating_server, protocol, container_id = nil)
    send("remote_console_#{protocol.to_s.downcase}_acquire_ticket", userid, originating_server, container_id)
  end

  def remote_console_acquire_ticket_queue(protocol, userid, container_id = nil)
    task_opts = {
      :action => "acquiring Pod #{name} #{protocol.to_s.upcase} remote console ticket for user #{userid}",
      :userid => userid
    }

    queue_opts = {
      :class_name  => self.class.name,
      :instance_id => id,
      :method_name => 'remote_console_acquire_ticket',
      :queue_name  => ext_management_system.queue_name_for_ems_operations,
      :priority    => MiqQueue::HIGH_PRIORITY,
      :role        => 'ems_operations',
      :zone        => my_zone,
      :args        => [userid, MiqServer.my_server.id, protocol, container_id]
    }

    MiqTask.generic_action_with_callback(task_opts, queue_opts)
  end

  def remote_console_kube_exec_acquire_ticket(userid, originating_server = nil, container_id = nil)
    validate_remote_console_acquire_ticket("kube_exec")

    SystemConsole.force_vm_invalid_token(id)

    api_uri = ext_management_system.api_endpoint
    container_id ||= containers.first&.id

    console_args = {
      :user         => User.find_by(:userid => userid),
      :container_id => container_id,
      :ssl          => true,
      :protocol     => 'kube_exec',
      :secret       => SecureRandom.hex,
      :url_secret   => SecureRandom.hex
    }

    SystemConsole.launch_proxy_if_not_local(console_args, originating_server, api_uri.host, api_uri.port)
  end
end
