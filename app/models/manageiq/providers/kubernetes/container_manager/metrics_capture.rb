module ManageIQ::Providers
  class Kubernetes::ContainerManager::MetricsCapture < ContainerManager::MetricsCapture
    include ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCaptureMixin

    def capture_ems_targets(_options = {})
      begin
        verify_metrics_connection!(ems)
      rescue TargetValidationError, TargetValidationWarning => e
        _log.send(e.log_severity, e.message)
        return []
      end

      super
    end
  end
end
