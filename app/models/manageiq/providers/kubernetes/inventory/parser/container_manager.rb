class ManageIQ::Providers::Kubernetes::Inventory::Parser::ContainerManager < ManageIQ::Providers::Kubernetes::Inventory::Parser
  def parse
    parse_pods(collector.pods)
  end

  private

  def parse_pods(pods)
    pods.each do |pod|
      persister.container_groups.build(
        :ems_ref          => pod.metadata.uid,
        :name             => pod.metadata.name,
        :namespace        => pod.metadata.namespace,
        :ems_created_on   => pod.metadata.creationTimestamp,
        :resource_version => pod.metadata.resourceVersion,
        :restart_policy   => pod.spec.restartPolicy,
        :dns_policy       => pod.spec.dnsPolicy,
        :ipaddress        => pod.status.podIP,
        :phase            => pod.status.phase,
        :message          => pod.status.message,
        :reason           => pod.status.reason,
      )
    end
  end
end
