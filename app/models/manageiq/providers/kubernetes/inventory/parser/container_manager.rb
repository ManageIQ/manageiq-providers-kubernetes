class ManageIQ::Providers::Kubernetes::Inventory::Parser::ContainerManager < ManageIQ::Providers::Kubernetes::Inventory::Parser
  def parse
    parse_namespaces(collector.namespaces)
    parse_pods(collector.pods)

    # Service catalog entities
    parse_service_offerings(collector.cluster_service_offerings)
    parse_service_parameters_sets(collector.cluster_service_parameters_sets)
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

  def parse_service_offerings(service_offeringes)
    service_offeringes.each do |service_offering|
      parse_service_offering(service_offering)
    end
  end

  def parse_service_offering(service_offering)
    persister.service_offerings.build(
      :name        => service_offering.spec.externalName,
      :ems_ref     => service_offering.spec.externalID,
      :description => service_offering.spec.description,
      :extra       => {
        :metadata => service_offering.metadata,
        :spec     => service_offering.spec,
        :status   => service_offering.status
      }
    )
  end

  def parse_service_parameters_sets(service_parameters_sets)
    service_parameters_sets.each do |service_parameters_set|
      parse_service_parameters_set(service_parameters_set)
    end
  end

  def parse_service_parameters_set(service_parameters_set)
    persister.service_parameters_sets.build(
      :name             => service_parameters_set.spec.externalName,
      :ems_ref          => service_parameters_set.spec.externalID,
      :description      => service_parameters_set.spec.description,
      :service_offering => persister.service_offerings.lazy_find(service_parameters_set.spec.clusterServiceClassRef.name),
      :extra            => {
        :metadata => service_parameters_set.metadata,
        :spec     => service_parameters_set.spec,
        :status   => service_parameters_set.status
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
