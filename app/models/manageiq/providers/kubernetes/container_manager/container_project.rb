class ManageIQ::Providers::Kubernetes::ContainerManager::ContainerProject < ::ContainerProject
  supports :create
  supports :delete

  def self.display_name(number = 1)
    n_('Container Project (Kubernetes)', 'Container Projects (Kubernetes)', number)
  end

  def self.raw_create_container_project(ext_management_system, options)
    project_name = options["name"]
    raise ArgumentError, _("Must specify a name for the container project") if project_name.blank?
    
    unless project_name.match?(/\A[a-z0-9]([-a-z0-9]*[a-z0-9])?\z/)
      raise ArgumentError, _("Name must consist of lower case alphanumeric characters or '-', start with an alphanumeric character, and end with an alphanumeric character")
    end
    
    if project_name.length > 63
      raise ArgumentError, _("Name must be no more than 63 characters")
    end

    labels = options.fetch("labels", {}).merge("name" => project_name)
    annotations = options["annotations"] || {}

    namespace_payload = Kubeclient::Resource.new(
      :apiVersion => "v1",
      :kind       => "Namespace",
      :metadata   => {
        :name        => project_name,
        :labels      => labels,
        :annotations => annotations
      }
    )

    core_client = ext_management_system.connect(:service => :kubernetes)
    result = core_client.create_namespace(namespace_payload)
    
    {:ems_ref => result.metadata.name, :name => result.metadata.name}
  rescue Kubeclient::HttpError => e
    if e.error_code == 409
      raise MiqException::Error, _("Container project '%{project_name}' already exists") % {:project_name => project_name}
    else
      raise MiqException::Error, "Kubernetes API error: #{e.message}"
    end
  rescue => e
    raise MiqException::Error, "Failed to create container project: #{e.message}", e.backtrace
  end

  def raw_delete_container_project
    connection = ext_management_system.connect(:service => :kubernetes)
    
    begin
      connection.delete_namespace(name)
    rescue Kubeclient::ResourceNotFoundError => e
      # Namespace already deleted, no action needed
    rescue Kubeclient::HttpError => e
      raise MiqException::Error, "Kubernetes API error: #{e.message}"
    rescue => e
      raise MiqException::Error, "Failed to delete container project: #{e.message}"
    end
  rescue => e
    raise MiqException::Error, "Failed to delete container project: #{e.message}", e.backtrace
  end
end
