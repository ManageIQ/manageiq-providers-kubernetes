module ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusClientMixin
  require 'faraday'

  def prometheus_client
    @prometheus_uri ||= prometheus_uri
    # TODO: [POC] Currently token is not implemented
    # @prometheus_credentials ||= prometheus_credentials
    @prometheus_options ||= prometheus_options

    # TODO: [POC] always use ssl
    # Faraday.new(
    #  :url     => @prometheus_uri.to_s,
    #  :ssl     => {
    #    :verify     => @prometheus_options[:verify_ssl] != OpenSSL::SSL::VERIFY_NONE,
    #    :cert_store => @prometheus_options[:ssl_cert_store]
    #  },
    #  :request => {
    #    :open_timeout => 2, # opening a connection
    #    :timeout      => 5  # waiting for response
    #  }
    # )

    Faraday.new(
      :url     => @prometheus_uri.to_s,
      :request => {
        :open_timeout => 2, # opening a connection
        :timeout      => 5  # waiting for response
      }
    )
  end

  # may be nil
  def prometheus_endpoint
    @ext_management_system.connection_configurations.prometheus.try(:endpoint)
  end

  def prometheus_uri
    prometheus_default_port = 80
    prometheus_default_hostname = @ext_management_system.hostname
    prometheus_endpoint_empty = prometheus_endpoint.try(:hostname).blank?

    URI::HTTP.build(
      :host => prometheus_endpoint_empty ? prometheus_default_hostname : prometheus_endpoint.hostname,
      :port => prometheus_endpoint_empty ? prometheus_default_port : prometheus_endpoint.port,
      :path => "/api/v1/"
    )
  end

  def prometheus_credentials
    {:token => @ext_management_system.try(:authentication_token)}
  end

  def prometheus_options
    {
      :http_proxy_uri => VMDB::Util.http_proxy_uri.to_s,
      :verify_ssl     => @ext_management_system.verify_ssl_mode(prometheus_endpoint),
      :ssl_cert_store => @ext_management_system.ssl_cert_store(prometheus_endpoint),
    }
  end

  def prometheus_try_connect
    # TODO: [POC] Currently not implemented
    true
  end
end
