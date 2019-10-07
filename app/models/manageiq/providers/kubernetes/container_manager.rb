class ManageIQ::Providers::Kubernetes::ContainerManager < ManageIQ::Providers::ContainerManager
  require_nested :Container
  require_nested :ContainerGroup
  require_nested :ContainerNode
  require_nested :ContainerTemplate
  require_nested :EventCatcher
  require_nested :EventCatcherMixin
  require_nested :EventParser
  require_nested :EventParserMixin
  require_nested :InventoryCollectorWorker
  require_nested :MetricsCapture
  require_nested :MetricsCollectorWorker
  require_nested :RefreshParser
  require_nested :RefreshWorker
  require_nested :Refresher
  require_nested :Scanning
  require_nested :Options

  include ManageIQ::Providers::Kubernetes::ContainerManagerMixin
  include ManageIQ::Providers::Kubernetes::ContainerManager::Options

  # See HasMonitoringManagerMixin
  has_one :monitoring_manager,
          :foreign_key => :parent_ems_id,
          :class_name  => "ManageIQ::Providers::Kubernetes::MonitoringManager",
          :autosave    => true,
          :dependent   => :destroy

  # This is the API version that we use and support throughout the entire code
  # (parsers, events, etc.). It should be explicitly selected here and not
  # decided by the user nor out of control in the defaults of kubeclient gem
  # because it's not guaranteed that the next default version will work with
  # our specific code in ManageIQ.
  delegate :api_version, :to => :class

  def api_version=(_value)
    raise 'Kubernetes api_version cannot be modified'
  end

  def self.api_version
    kubernetes_version
  end

  def self.ems_type
    @ems_type ||= "kubernetes".freeze
  end

  def self.description
    @description ||= "Kubernetes".freeze
  end

  def self.params_for_create
    @params_for_create ||= {
      :title  => "Configure #{description}",
      :fields => [
        {
          :component  => "text-field",
          :name       => "endpoints.default.hostname",
          :label      => "Hostname",
          :isRequired => true,
          :validate   => [{:type => "required-validator"}]
        },
        {
          :component  => "text-field",
          :name       => "endpoints.default.port",
          :type       => "number",
          :isRequired => true,
          :validate   => [
            {
              :type => "required-validator"
            },
            {
              :type             => "validatorTypes.MIN_NUMBER_VALUE",
              :includeThreshold => true,
              :value            => 1
            },
            {
              :type             => "validatorTypes.MAX_NUMBER_VALUE",
              :includeThreshold => true,
              :value            => 65_535
            }
          ]
        },
        {
          :component    => "text-field",
          :name         => "endpoints.default.path",
          :label        => "API Path",
          :type         => "hidden",
          :initialValue => "/api"
        },
        {
          :component  => "text-field",
          :name       => "endpoints.default.bearer",
          :label      => "Token",
          :type       => "password",
          :isRequired => true,
          :validate   => [{:type => "required-validator"}]
        },
        {
          :component => "text-field",
          :name      => "endpoints.default.http_proxy",
          :label     => "HTTP Proxy"
        },
        {
          :component => "checkbox",
          :name      => "endpoints.default.verify_ssl",
          :label     => "Verify SSL"
        },
        {
          :component => "text-field",
          :name      => "endpoints.default.ca_file",
          :label     => "Trusted CA Certificates",
        },
      ]
    }.freeze
  end

  def self.verify_credentials(args)
    default_endpoint = args.dig("endpoints", "default")
    hostname, port = default_endpoint&.values_at("hostname", "port")

    options = default_endpoint&.slice("path", "http_proxy")&.symbolize_keys || {}

    bearer = default_endpoint&.dig("bearer")
    options[:bearer] = MiqPassword.try_decrypt(bearer) if bearer

    options[:ssl_options] = {
      :verify_ssl => default_endpoint&.dig("verify_ssl") ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE,
      :ca_file    => default_endpoint&.dig("ca_file")
    }

    !!raw_connect(hostname, port, options)
  end

  def self.raw_connect(hostname, port, options)
    kubernetes_connect(hostname, port, options)
  end

  def self.event_monitor_class
    ManageIQ::Providers::Kubernetes::ContainerManager::EventCatcher
  end

  def self.display_name(number = 1)
    n_('Container Provider (Kubernetes)', 'Container Providers (Kubernetes)', number)
  end
end
