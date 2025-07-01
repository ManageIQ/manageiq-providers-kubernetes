class ManageIQ::Providers::Kubernetes::ContainerManager::ContainerProject < ::ContainerProject
  supports :create
  supports :update
  supports :delete

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

  def raw_update_container_project(options)
    namespace_name = name
    resource_data = options["resource"]
    
    if resource_data.key?("name")
      new_name = resource_data["name"]
      if new_name.present? && new_name != name
        raise MiqException::Error, "Cannot rename namespace '#{name}' to '#{new_name}' - namespace names are immutable in Kubernetes"
      end
    end
    
    core_client = ext_management_system.connect(:service => :kubernetes)
    current_namespace = core_client.get_namespace(namespace_name)
    
    current_metadata = current_namespace.metadata.to_h
    updated_metadata = {
      :name => current_metadata[:name] || current_metadata["name"],
      :labels => current_metadata[:labels] || current_metadata["labels"] || {},
      :annotations => current_metadata[:annotations] || current_metadata["annotations"] || {},
      :resourceVersion => current_metadata[:resourceVersion] || current_metadata["resourceVersion"]
    }
    
    updated_metadata[:labels] = updated_metadata[:labels].to_h.stringify_keys
    updated_metadata[:annotations] = updated_metadata[:annotations].to_h.stringify_keys
    
    updates_made = []
    
    if resource_data.key?("labels")
      new_labels = resource_data["labels"]
      if new_labels.present?
        updated_metadata[:labels].merge!(new_labels.stringify_keys)
        updates_made << "labels"
      end
    end
    
    if resource_data.key?("annotations")
      new_annotations = resource_data["annotations"]
      if new_annotations.present?
        updated_metadata[:annotations].merge!(new_annotations.stringify_keys)
        updates_made << "annotations"
      end
    end
    
    return if updates_made.empty?
    
    namespace_resource = Kubeclient::Resource.new(
      :apiVersion => current_namespace.apiVersion,
      :kind       => current_namespace.kind,
      :metadata   => updated_metadata
    )
    
    core_client.update_namespace(namespace_resource)
  rescue Kubeclient::ResourceNotFoundError => e
    raise MiqException::Error, "Namespace '#{namespace_name}' not found in Kubernetes cluster"
  rescue Kubeclient::HttpError => e
    raise MiqException::Error, "Kubernetes API error: #{e.message}"
  rescue => e
    raise MiqException::Error, "Failed to update container project: #{e.message}", e.backtrace
  end

  def raw_delete_container_project
    namespace_name = name
    connection = ext_management_system.connect(:service => :kubernetes)
    
    begin
      connection.get_namespace(namespace_name)
      connection.delete_namespace(namespace_name)
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

  def self.display_name(number = 1)
    n_('Container Project (Kubernetes)', 'Container Projects (Kubernetes)', number)
  end
end
