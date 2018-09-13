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

      persister.container_projects.targeted_scope << namespace.metadata.uid
      next if notice.type == "DELETED"

      parse_namespace(namespace)
    end
  end

  def parse_pod_notices(pod_notices)
    pod_notices.each do |notice|
      pod = notice.object

      persister.container_groups.targeted_scope << pod.metadata.uid
      next if notice.type == "DELETED"

      parse_pod(pod)
    end
  end

  def parse_service_class_notices(service_class_notices)
    service_class_notices.each do |notice|
      service_class = notice.object

      persister.service_offerings.targeted_scope << service_class.spec.externalID
      next if notice.type == "DELETED"

      parse_service_class(service_class)
    end
  end

  def parse_service_plan_notices(service_plan_notices)
    service_plan_notices.each do |notice|
      service_plan = notice.object

      persister.service_parameters_sets.targeted_scope << service_plan.spec.externalID
      next if notice.type == "DELETED"

      parse_service_plan(service_plan)
    end
  end
end
