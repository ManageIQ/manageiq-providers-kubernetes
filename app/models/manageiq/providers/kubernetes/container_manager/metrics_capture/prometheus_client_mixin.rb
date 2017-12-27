module ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusClientMixin
  require 'faraday'

  def prometheus_client
    @prometheus_uri ||= prometheus_uri
    @prometheus_credentials ||= prometheus_credentials
    @prometheus_options ||= prometheus_options

    prometheus_client_new(@prometheus_uri, @prometheus_credentials, @prometheus_options)
  end

  def prometheus_client_new(uri, credentials, options)
    worker_class = ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCollectorWorker

    Faraday.new(
      :url     => uri.to_s,
      :proxy   => options[:http_proxy_uri].empty? ? nil : options[:http_proxy_uri],
      :ssl     => {
        :verify     => options[:verify_ssl] != OpenSSL::SSL::VERIFY_NONE,
        :cert_store => options[:ssl_cert_store]
      },
      :request => {
        :open_timeout => worker_class.worker_settings[:prometheus_open_timeout] || 5,
        :timeout      => worker_class.worker_settings[:prometheus_request_timeout] || 30
      },
      :headers => {
        :Authorization => "Bearer " + credentials[:token]
      }
    )
  end

  def prometheus_endpoint
    @ext_management_system.connection_configurations.prometheus.endpoint
  end

  def prometheus_uri
    URI::HTTPS.build(
      :host => prometheus_endpoint.hostname,
      :port => prometheus_endpoint.port,
      :path => "/api/v1/"
    )
  end

  def prometheus_credentials
    {:token => @ext_management_system.authentication_token("prometheus")}
  end

  def prometheus_options
    {
      :http_proxy_uri => VMDB::Util.http_proxy_uri.to_s,
      :verify_ssl     => @ext_management_system.verify_ssl_mode(prometheus_endpoint),
      :ssl_cert_store => @ext_management_system.ssl_cert_store(prometheus_endpoint),
    }
  end

  def labels_to_s(labels, job = "kubernetes-cadvisor")
    labels.merge(:job => job).compact.sort.map { |k, v| "#{k}=\"#{v}\"" }.join(',')
  end

  def prometheus_try_connect
    begin
      response = prometheus_client.get("query", :query => "ALL")
    rescue StandardError => err
      raise MiqException::MiqUnreachableError, err.message, err.backtrace
    end

    begin
      data = JSON.parse(response.body)
    rescue StandardError => err # if auth_proxy fail it returns an html doc
      raise MiqException::MiqInvalidCredentialsError, err.message, err.backtrace
    end

    data.kind_of?(Hash)
  end
end
