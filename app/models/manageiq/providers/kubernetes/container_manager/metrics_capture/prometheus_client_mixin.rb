module ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusClientMixin
  require 'prometheus/api_client'

  def prometheus_client
    @prometheus_uri ||= prometheus_uri
    @prometheus_credentials ||= prometheus_credentials
    @prometheus_options ||= prometheus_options

    prometheus_client_new(@prometheus_uri, @prometheus_credentials, @prometheus_options)
  end

  def prometheus_client_new(uri, credentials, options)
    Prometheus::ApiClient.client(
      :url         => uri.to_s,
      :options     => options,
      :credentials => credentials
    )
  end

  def prometheus_endpoint
    @ext_management_system.connection_configurations.prometheus.endpoint
  end

  def prometheus_uri
    URI::HTTPS.build(
      :host => prometheus_endpoint.hostname,
      :port => prometheus_endpoint.port,
    )
  end

  def prometheus_credentials
    {:token => @ext_management_system.authentication_token("prometheus")}
  end

  def prometheus_options
    worker_class = ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCollectorWorker

    {
      :http_proxy_uri => VMDB::Util.http_proxy_uri.to_s,
      :verify_ssl     => @ext_management_system.verify_ssl_mode(prometheus_endpoint),
      :ssl_cert_store => @ext_management_system.ssl_cert_store(prometheus_endpoint),
      :open_timeout   => worker_class.worker_settings[:prometheus_open_timeout] || 5,
      :timeout        => worker_class.worker_settings[:prometheus_request_timeout] || 30
    }
  end

  def labels_to_s(labels, job = "kubelet")
    labels.merge(:job => job).compact.sort.map { |k, v| "#{k}=\"#{v}\"" }.join(',')
  end

  def prometheus_try_connect
    # NOTE: we do not catch errors from prometheus_client here
    #       prometheus_client will raise specific errors in case of connection
    #       errors
    data = prometheus_client.query(:query => "ALL")
    data.kind_of?(Hash)
  end
end
