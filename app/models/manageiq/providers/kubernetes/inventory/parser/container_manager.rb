class ManageIQ::Providers::Kubernetes::Inventory::Parser::ContainerManager < ManageIQ::Providers::Kubernetes::Inventory::Parser
  def parse
    parse_namespaces(collector.namespaces)
    parse_pods(collector.pods)
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
