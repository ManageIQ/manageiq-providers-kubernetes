class ManageIQ::Providers::Kubernetes::ContainerManager::Container < ::Container
  include ActsAsStiLeafClass

  delegate :pod_uid, :to => :container_group
end
