class ManageIQ::Providers::Kubernetes::Inventory::Parser::Watches < ManageIQ::Providers::Kubernetes::Inventory::Parser
  def parse
    parse_pods(collector.notices["Pod"])
  end

  private

  def parse_pods(pod_notices)
    pod_notices.to_a.each do |pod_notice|
      next if pod_notice.type == "DELETED"

      pod = pod_notice.object

      persister.container_groups.build(
        :ems_ref             => pod.metadata.uid,
        :name                => pod.metadata.name,
        :namespace           => pod.metadata.namespace,
        :ems_created_on      => pod.metadata.creationTimestamp,
        :resource_version    => pod.metadata.resourceVersion,
        :restart_policy      => pod.spec.restartPolicy,
        :dns_policy          => pod.spec.dnsPolicy,
        :ipaddress           => pod.status.podIP,
        :phase               => pod.status.phase,
        :message             => pod.status.message,
        :reason              => pod.status.reason,
        :container_node_name => pod.spec.nodeName,
        :build_pod_name      => pod.metadata.try(:annotations).try("openshift.io/build.name".to_sym)
      )
    end
  end
end
