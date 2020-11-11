module ManageIQ::Providers
  class Kubernetes::MonitoringManager < ManageIQ::Providers::MonitoringManager
    require_nested :EventCatcher

    ENDPOINT_ROLE = :prometheus_alerts


    belongs_to :parent_manager,
               :foreign_key => :parent_ems_id,
               :class_name  => "ManageIQ::Providers::Kubernetes::ContainerManager",
               :inverse_of  => :monitoring_manager

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

    def self.ems_type
      @ems_type ||= "kubernetes_monitor".freeze
    end

    def self.description
      @description ||= "Kubernetes Monitor".freeze
    end

    def self.event_monitor_class
      ManageIQ::Providers::Kubernetes::MonitoringManager::EventCatcher
    end

    def self.verify_credentials(options)
      raw_connect(options)&.get&.key?('generationID')
    rescue OpenSSL::X509::CertificateError => err
      raise MiqException::MiqInvalidCredentialsError, "SSL Error: #{err.message}"
    rescue Faraday::ParsingError
      raise MiqException::MiqUnreachableError, 'Unexpected Response'
    rescue Faraday::ClientError => err
      raise MiqException::MiqUnreachableError, err.message
    rescue => err
      raise MiqException::MiqUnreachableError, err.message, err.backtrace
    end

    def self.raw_connect(options)
      require 'prometheus/alert_buffer_client'
      Prometheus::AlertBufferClient::Client.new(options)
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
      parent_manager.verify_ssl_mode(prometheus_alerts_endpoint) == OpenSSL::SSL::VERIFY_PEER
    end
  end
end
