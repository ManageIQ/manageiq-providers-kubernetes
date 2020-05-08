class ManageIQ::Providers::Kubernetes::ContainerManager::RefreshWorker < ManageIQ::Providers::BaseManager::RefreshWorker
  require_nested :Runner
  require_nested :WatchThread
end
