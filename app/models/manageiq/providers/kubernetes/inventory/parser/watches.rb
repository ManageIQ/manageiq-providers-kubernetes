class ManageIQ::Providers::Kubernetes::Inventory::Parser::Watches < ManageIQ::Providers::Kubernetes::Inventory::Parser::ContainerManager
  def parse
    parse_pods(collector.notices["Pod"])
  end

  private

  def parse_pods(pod_notices)
    pod_notices.to_a.each do |pod_notice|
      persister.container_groups.targeted_scope << pod_notice.object.metadata.uid
      next if pod_notice.type == "DELETED"

      parse_pod(pod_notice.object)
    end
  end
end
