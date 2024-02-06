class ManageIQ::Providers::Kubernetes::MonitoringManager::EventCatcher < ManageIQ::Providers::BaseManager::EventCatcher
  def self.settings_name
    :event_catcher_prometheus
  end
end
