autoload(:KubeException, 'kubeclient')

module ManageIQ::Providers::Kubernetes::ContainerManager::ContainerTemplateMixin
  extend ActiveSupport::Concern
  include ManageIQ::Providers::Kubernetes::ContainerManager::EntitiesMapping

  def instantiate(params, project = nil, labels = nil)
    project ||= container_project.name
    labels  ||= object_labels
    processed_template = process_template(ext_management_system.connect,
                                          :metadata   => {
                                            :name      => name,
                                            :namespace => project
                                          },
                                          :objects    => objects,
                                          :parameters => params.collect(&:instantiation_attributes),
                                          :labels     => labels)
    create_objects(processed_template['objects'], project)
    @created_objects.each { |obj| obj[:miq_class] = model_by_entity(obj[:kind].underscore) }
  end

  def process_template(client, template)
    client.process_template(template)
  rescue KubeException => e
    raise MiqException::MiqProvisionError, "Unexpected Exception while processing template: #{e}"
  end

  def create_objects(objects, project)
    @created_objects = []
    objects.each { |obj| @created_objects << create_object(obj, project).to_h }
  end

  def create_object(obj, project)
    obj = obj.symbolize_keys
    obj[:metadata][:namespace] = project
    method_name = "create_#{obj[:kind].underscore}"
    begin
      ext_management_system.connect_client(obj[:apiVersion], method_name).send(method_name, obj)
    rescue KubeException => e
      rollback_objects(@created_objects)
      raise MiqException::MiqProvisionError, "Unexpected Exception while creating object: #{e}"
    end
  end

  # rollback_objects cannot catch children objects created during the template instantiation and therefore those objects
  # will remain in the cluster.
  def rollback_objects(objects)
    objects.each { |obj| rollback_object(obj) }
  end

  def rollback_object(obj)
    method_name = "delete_#{obj[:kind].underscore}"
    begin
      ext_management_system.connect_client(obj[:apiVersion], method_name).send(method_name,
                                                                               obj[:metadata][:name],
                                                                               obj[:metadata][:namespace])
    rescue KubeException => e
      _log.error("Unexpected Exception while deleting object: #{e}")
    end
  end
end
