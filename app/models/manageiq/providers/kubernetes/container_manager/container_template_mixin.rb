module ManageIQ::Providers::Kubernetes::ContainerManager::ContainerTemplateMixin
  extend ActiveSupport::Concern

  MIQ_ENTITY_MAPPING = {
    "Route"                 => ContainerRoute,
    "Build"                 => ContainerBuildPod,
    "BuildConfig"           => ContainerBuild,
    "Template"              => ContainerTemplate,
    "ResourceQuota"         => ContainerQuota,
    "LimitRange"            => ContainerLimit,
    "ReplicationController" => ContainerReplicator,
    "PersistentVolumeClaim" => PersistentVolumeClaim,
    "Pod"                   => ContainerGroup,
    "Service"               => ContainerService,
  }.freeze

  def instantiate(params, project = nil)
    project ||= container_project.name
    processed_template = process_template(ext_management_system.connect,
                                          :metadata   => {
                                            :name      => name,
                                            :namespace => project
                                          },
                                          :objects    => objects,
                                          :parameters => params)
    create_objects(processed_template['objects'], project)
    @created_objects.each { |obj| obj[:miq_class] = MIQ_ENTITY_MAPPING[obj[:kind]] }
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
