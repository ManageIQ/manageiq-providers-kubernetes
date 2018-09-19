class ManageIQ::Providers::Kubernetes::Inventory::Parser::Watches < ManageIQ::Providers::Kubernetes::Inventory::Parser::ContainerManager
  def parse
    parse_namespace_notices(collector.namespace_notices)
    parse_pod_notices(collector.pod_notices)

    # Service catalog entities
    parse_service_class_notices(collector.cluster_service_class_notices)
    parse_service_plan_notices(collector.cluster_service_plan_notices)
  end

  private

  def parse_namespace_notices(namespace_notices)
    namespace_notices.each do |notice|
      namespace = notice.object
      ns_inv_obj = parse_namespace(namespace)
      assign_deleted_on(ns_inv_obj, namespace) if notice.type == "DELETED"
    end
  end

  def parse_pod_notices(pod_notices)
    pod_notices.each do |notice|
      pod = notice.object
      pod_inv_obj = parse_pod(pod)
      assign_deleted_on(pod_inv_obj, pod) if notice.type == "DELETED"
    end
  end

  def parse_service_class_notices(service_class_notices)
    service_class_notices.each do |notice|
      service_class = notice.object
      service_class_inv_obj = parse_service_class(service_class)
      assign_deleted_on(service_class_inv_obj, service_class) if notice.type == "DELETED"
    end
  end

  def parse_service_plan_notices(service_plan_notices)
    service_plan_notices.each do |notice|
      service_plan = notice.object
      service_plan_inv_obj = parse_service_plan(service_plan)
      assign_deleted_on(service_plan_inv_obj, service_plan) if notice.type == "DELETED"
    end
  end

  def assign_deleted_on(inv_obj, object)
    inv_obj.data[:deleted_on] = object.metadata.deletionTimestamp || Time.now.utc
  end
end
