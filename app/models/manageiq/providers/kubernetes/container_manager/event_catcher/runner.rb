class ManageIQ::Providers::Kubernetes::ContainerManager::EventCatcher::Runner < ManageIQ::Providers::BaseManager::EventCatcher::Runner
  include ManageIQ::Providers::Kubernetes::ContainerManager::EventCatcherMixin

  private

  def worker_cmdline
    ManageIQ::Providers::Kubernetes::Engine.root.join("workers/manageiq/providers/kubernetes/container_manager/event_catcher/worker").to_s
  end
end
