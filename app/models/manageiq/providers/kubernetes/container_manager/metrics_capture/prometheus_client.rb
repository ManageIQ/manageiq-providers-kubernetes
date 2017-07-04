class ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusClient
  include ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusClientMixin

  def initialize(ext_management_system)
    @ext_management_system = ext_management_system
  end
end
