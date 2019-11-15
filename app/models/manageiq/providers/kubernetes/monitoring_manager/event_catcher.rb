class ManageIQ::Providers::Kubernetes::MonitoringManager::EventCatcher < ManageIQ::Providers::BaseManager::EventCatcher
  require_nested :Runner
  require_nested :RunnerMixin
  require_nested :Stream

  def self.settings_name
    :event_catcher_prometheus
  end
end
