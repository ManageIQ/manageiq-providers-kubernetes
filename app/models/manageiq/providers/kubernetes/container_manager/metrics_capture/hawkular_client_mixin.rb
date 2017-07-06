module ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::HawkularClientMixin
  def hawkular_client(tenant = nil)
    require 'hawkular/hawkular_client'

    @hawkular_uri ||= hawkular_uri
    @hawkular_credentials ||= hawkular_credentials
    @hawkular_options ||= hawkular_options

    if tenant
      Hawkular::Metrics::Client.new(@hawkular_uri, @hawkular_credentials, @hawkular_options.merge(:tenant => tenant))
    else
      Hawkular::Metrics::Client.new(@hawkular_uri, @hawkular_credentials, @hawkular_options)
    end
  end

  # may be nil
  def hawkular_endpoint
    @ext_management_system.connection_configurations.hawkular.try(:endpoint)
  end

  def hawkular_uri
    hawkular_endpoint_empty = hawkular_endpoint.try(:hostname).blank?
    worker_class = ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCollectorWorker

    URI::HTTPS.build(
      :host => hawkular_endpoint_empty ? @ext_management_system.hostname : hawkular_endpoint.hostname,
      :port => hawkular_endpoint_empty ? worker_class.worker_settings[:metrics_port] : hawkular_endpoint.port,
      :path => worker_class.worker_settings[:metrics_path] || '/hawkular/metrics')
  end

  def hawkular_credentials
    {:token => @ext_management_system.try(:authentication_token)}
  end

  def hawkular_options
    {
      :tenant         => @tenant,
      :http_proxy_uri => VMDB::Util.http_proxy_uri.to_s,
      :verify_ssl     => @ext_management_system.verify_ssl_mode(hawkular_endpoint),
      :ssl_cert_store => @ext_management_system.ssl_cert_store(hawkular_endpoint),
    }
  end

  def hawkular_compatbility_matrix
    return {} unless @ext_management_system

    cli = hawkular_client("_system").gauges
    {
      :has_allocatable => cli.query(:descriptor_name => "cpu/node_allocatable").compact.any?,
      :has_rate        => cli.query(:descriptor_name => "cpu/usage_rate").compact.any?,
      :has_rss         => cli.query(:descriptor_name => "memory/rss").compact.any?
    }
  end

  def hawkular_try_connect
    # check the connection and the credentials by trying
    # to access hawkular's availability private data, and fetch one line of data.
    # this will check the connection and the credentials
    # because only if the connection is ok, and the token is valid,
    # we will get an OK response, with an array of data, or an empty array
    # if no data availabel.
    hawkular_client.avail.get_data("all", :limit => 1).kind_of?(Array)
  end
end
