class ManageIQ::Providers::Kubernetes::ContainerManager::EventCatcher < ManageIQ::Providers::BaseManager::EventCatcher
  self.rails_worker = -> { !!worker_settings[:rails_worker] }
  self.worker_settings_paths = [%i[ems ems_kubernetes]]
end
