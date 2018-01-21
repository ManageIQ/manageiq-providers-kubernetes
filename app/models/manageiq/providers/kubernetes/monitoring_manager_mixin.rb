module ManageIQ::Providers::Kubernetes::MonitoringManagerMixin
  extend ActiveSupport::Concern
  require 'prometheus/alert_buffer_client'

  ENDPOINT_ROLE = :prometheus_alerts

  included do
    delegate :authentication_check,
             :authentication_for_summary,
             :authentication_status,
             :authentication_status_ok,
             :authentication_token,
             :authentications,
             :endpoints,
             :zone,
             :to        => :parent_manager,
             :allow_nil => true

    def self.hostname_required?
      false
    end
  end

  module ClassMethods
    def raw_connect(options)
      Prometheus::AlertBufferClient::Client.new(options)
    end
  end

  def prometheus_alerts_endpoint
    connection_configurations.prometheus_alerts.try(:endpoint)
  end

  def verify_credentials(_auth_type = nil, _options = {})
    with_provider_connection do |conn|
      conn.get.key?('generationID')
    end
  rescue OpenSSL::X509::CertificateError => err
    raise MiqException::MiqInvalidCredentialsError, "SSL Error: #{err.message}"
  rescue Faraday::ParsingError
    raise MiqException::MiqUnreachableError, 'Unexpected Response'
  rescue Faraday::ClientError => err
    raise MiqException::MiqUnreachableError, err.message
  rescue StandardError => err
    raise MiqException::MiqUnreachableError, err.message, err.backtrace
  end

  def connect(_options = {})
    settings = ::Settings.ems.ems_kubernetes.ems_monitoring.alerts_collection
    self.class.raw_connect(
      :url         => "https://#{prometheus_alerts_endpoint.hostname}:#{prometheus_alerts_endpoint.port}",
      :path        => "/topics/alerts",
      :credentials => {:token => authentication_token},
      :ssl         => {:verify     => verify_ssl,
                       :cert_store => ssl_cert_store},
      :request     => {:open_timeout => settings.open_timeout.to_f_with_method,
                       :timeout      => settings.timeout.to_f_with_method},
      :proxy       => parent_manager.options ? parent_manager.options.fetch_path(:proxy_settings, :http_proxy) : nil,
    )
  end

  def default_authentication_type
    ENDPOINT_ROLE
  end

  def ssl_cert_store
    # nil === use system CA bundle
    prometheus_alerts_endpoint.try(:ssl_cert_store)
  end

  def verify_ssl
    prometheus_alerts_endpoint.verify_ssl?
  end
end
