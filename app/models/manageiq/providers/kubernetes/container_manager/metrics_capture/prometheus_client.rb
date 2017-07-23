class ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusClient
  include ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusClientMixin

  def initialize(ext_management_system, tenant = '_system')
    @ext_management_system = ext_management_system
    @tenant = tenant
  end
end
