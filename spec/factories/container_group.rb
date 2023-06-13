FactoryBot.define do
  factory :kubernetes_container_group,
          :parent => :container_group,
          :class  => "ManageIQ::Providers::Kubernetes::ContainerManager::ContainerGroup"
end
