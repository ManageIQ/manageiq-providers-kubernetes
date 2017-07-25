module ManageIQ::Providers::Kubernetes::MonitoringManagerMixin
  extend ActiveSupport::Concern
  ENDPOINT_ROLE = :prometheus_alerts
  DEFAULT_PORT = 9093
  included do
    delegate :authentications,
             :endpoints,
             :to        => :parent_manager,
             :allow_nil => true

    default_value_for :port do |manager|
      manager.port || DEFAULT_PORT
    end
  end

  module ClassMethods
    def raw_connect(hostname, port, options)
      ManageIQ::Providers::Kubernetes::Prometheus::MessageBufferClient.new(hostname, port).connect(options)
    end
  end

  def default_endpoint
    endpoints && endpoints.detect { |x| x.role == ENDPOINT_ROLE.to_s }
  end

  def supports_port?
    true
  end

  # Authentication related methods, see AuthenticationMixin
  def authentications_to_validate
    [ENDPOINT_ROLE]
  end

  def required_credential_fields(_type)
    [:auth_key]
  end

  def default_authentication_type
    ENDPOINT_ROLE
  end

  def verify_credentials(auth_type = nil, options = {})
    with_provider_connection(options.merge(:auth_type => auth_type)) do |conn|
      # TODO: move to a client method, once we have one
      conn.get.body.key?('generationID')
    end
  rescue Faraday::ClientError => err
    raise MiqException::MiqUnreachableError, err.message, err.backtrace
  end

  def connect(options = {})
    self.class.raw_connect(
      options[:hostname] || hostname,
      options[:port] || port,
      :bearer     => options[:bearer] || authentication_token(options[:auth_type] || 'bearer'),
      :verify_ssl => options[:verify_ssl] || verify_ssl,
      :cert_store => options[:cert_store] || ssl_cert_store
    )
  end

  def ssl_cert_store
    # nil === use system CA bundle
    default_endpoint.try(:ssl_cert_store)
  end

  def verify_ssl
    default_endpoint.verify_ssl?
  end
end
