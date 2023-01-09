class ManageIQ::Providers::Kubernetes::ContainerManager::Container < ::Container
  supports :capture

  delegate :pod_uid, :to => :container_group
end
