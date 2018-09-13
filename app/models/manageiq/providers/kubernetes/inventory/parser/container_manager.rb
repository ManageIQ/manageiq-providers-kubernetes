class ManageIQ::Providers::Kubernetes::Inventory::Parser::ContainerManager < ManageIQ::Providers::Kubernetes::Inventory::Parser
  def parse
    parse_namespaces(collector.namespaces)
    parse_pods(collector.pods)

    # Service catalog entities
    parse_service_classes(collector.cluster_service_classes)
    parse_service_plans(collector.cluster_service_plans)
  end

  private

  def parse_namespaces(namespaces)
    namespaces.each { |ns| parse_namespace(ns) }
  end

  def parse_namespace(namespace)
    persister.container_projects.build(
      parse_base_item(namespace).except(:namespace)
    )
  end

  def parse_pods(pods)
    pods.each { |pod| parse_pod(pod) }
  end

  def parse_pod(pod)
    persister.container_groups.build(
      parse_base_item(pod).merge(
        :restart_policy    => pod.spec.restartPolicy,
        :dns_policy        => pod.spec.dnsPolicy,
        :ipaddress         => pod.status.podIP,
        :phase             => pod.status.phase,
        :message           => pod.status.message,
        :reason            => pod.status.reason,
        :container_project => lazy_find_project(pod),
      )
    )
  end

  def parse_service_classes(service_classes)
    service_classes.each do |service_class|
      parse_service_class(service_class)
    end
  end

  def parse_service_class(service_class)
    persister.service_offerings.build(
      :name        => service_class.spec.externalName,
      :ems_ref     => service_class.spec.externalID,
      :description => service_class.spec.description,
      :extra       => {
        :metadata => service_class.metadata,
        :spec     => service_class.spec,
        :status   => service_class.status
      }
    )
  end

  def parse_service_plans(service_plans)
    service_plans.each do |service_plan|
      parse_service_plan(service_plan)
    end
  end

  def parse_service_plan(service_plan)
    persister.service_parameters_sets.build(
      :name             => service_plan.spec.externalName,
      :ems_ref          => service_plan.spec.externalID,
      :description      => service_plan.spec.description,
      :service_offering => persister.service_offerings.lazy_find(service_plan.spec.clusterServiceClassRef.name),
      :extra            => {
        :metadata => service_plan.metadata,
        :spec     => service_plan.spec,
        :status   => service_plan.status
      }
    )
  end

  def parse_base_item(item)
    {
      :ems_ref          => item.metadata.uid,
      :name             => item.metadata.name,
      :namespace        => item.metadata.namespace,
      :ems_created_on   => item.metadata.creationTimestamp,
      :resource_version => item.metadata.resourceVersion
    }
  end

  def lazy_find_project(object, namespace: nil)
    namespace ||= object&.metadata&.namespace
    return if namespace.nil?

    persister.container_projects.lazy_find(namespace, :ref => :by_name)
  end
end
