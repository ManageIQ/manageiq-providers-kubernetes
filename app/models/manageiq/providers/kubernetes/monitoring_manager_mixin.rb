module ManageIQ::Providers::Kubernetes::MonitoringManagerMixin
  extend ActiveSupport::Concern

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
  end

  module ClassMethods
    def raw_connect(hostname, port, options)
      ManageIQ::Providers::Kubernetes::Prometheus::MessageBufferClient.new(hostname, port).connect(options)
    end
  end

  def prometheus_alerts_endpoint
    connection_configurations.prometheus_alerts.try(:endpoint)
  end

  def verify_credentials(_auth_type = nil, _options = {})
    with_provider_connection do |conn|
      conn.get.body.key?('generationID')
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

  def connect(options = {})
    self.class.raw_connect(
      options[:hostname] || prometheus_alerts_endpoint.hostname,
      options[:port] || prometheus_alerts_endpoint.port,
      :bearer     => options[:bearer] || authentication_token, # goes to the default endpoint
      :verify_ssl => options[:verify_ssl] || verify_ssl,
      :cert_store => options[:cert_store] || ssl_cert_store
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
