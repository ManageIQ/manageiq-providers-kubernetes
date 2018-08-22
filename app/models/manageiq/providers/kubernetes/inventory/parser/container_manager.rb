class ManageIQ::Providers::Kubernetes::Inventory::Parser::ContainerManager < ManageIQ::Providers::Kubernetes::Inventory::Parser
  def parse
    parse_namespaces(collector.namespaces)
    parse_pods(collector.pods)

    # Service catalog entities
    parse_container_service_classes(collector.cluster_service_classes)
    parse_container_service_instances(collector.service_instances)
    parse_container_service_plans(collector.cluster_service_plans)
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

  def parse_container_service_classes(service_classes)
    service_classes.each do |service_class|
      parse_container_service_class(service_class)
    end
  end

  def parse_container_service_class(service_class)
    persister.container_service_classes.build(
      parse_base_item(service_class).except(:namespace, :ems_ref, :name).merge(
        :name              => service_class.spec.externalName,
        :ems_ref           => service_class.spec.externalID,
        :description       => service_class.spec.description,
        :container_project => lazy_find_project(service_class),
        :extra             => {
          :spec   => service_class.spec,
          :status => service_class.status
        }
      )
    )
  end

  def parse_container_service_instances(service_instances)
    service_instances.each do |service_instance|
      parse_container_service_instance(service_instance)
    end
  end

  def parse_container_service_instance(service_instance)
    persister.container_service_instances.build(
      parse_base_item(service_instance).except(:namespace, :ems_ref).merge(
        :ems_ref                 => service_instance.spec.externalID,
        :generate_name           => service_instance.metadata.generate_name,
        :container_project       => lazy_find_project(service_instance),
        :container_service_class => persister.container_service_classes.lazy_find(
          service_instance.spec.clusterServiceClassRef.name
        ),
        :container_service_plan  => persister.container_service_plans.lazy_find(
          service_instance.spec.clusterServicePlanRef.name
        ),
        :extra                   => {
          :spec   => service_instance.spec,
          :status => service_instance.status
        }
      )
    )
  end

  def parse_container_service_plans(service_plans)
    service_plans.each do |service_plan|
      parse_container_service_plan(service_plan)
    end
  end

  def parse_container_service_plan(service_plan)
    persister.container_service_plans.build(
      parse_base_item(service_plan).except(:namespace, :ems_ref, :name).merge(
        :name                    => service_plan.spec.externalName,
        :ems_ref                 => service_plan.spec.externalID,
        :description             => service_plan.spec.description,
        :container_project       => lazy_find_project(service_plan),
        :container_service_class => persister.container_service_classes.lazy_find(
          service_plan.spec.clusterServiceClassRef.name
        ),
        :extra                   => {
          :spec   => service_plan.spec,
          :status => service_plan.status
        }
      )
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
