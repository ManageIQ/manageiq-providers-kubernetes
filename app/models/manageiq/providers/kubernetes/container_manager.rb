class ManageIQ::Providers::Kubernetes::ContainerManager < ManageIQ::Providers::ContainerManager
  DEFAULT_PORT = 6443
  METRICS_ROLES = %w[prometheus].freeze

  has_one :infra_manager,
          :foreign_key => :parent_ems_id,
          :class_name  => "ManageIQ::Providers::Kubevirt::InfraManager",
          :autosave    => true,
          :inverse_of  => :parent_manager,
          :dependent   => :destroy

  include HasInfraManagerMixin
  include ManageIQ::Providers::Kubernetes::ContainerManager::Options

  before_save :stop_event_monitor_queue_on_change, :stop_refresh_worker_queue_on_change
  before_destroy :stop_event_monitor, :stop_refresh_worker

  supports :create
  supports :streaming_refresh do
    _("Streaming refresh not enabled") unless streaming_refresh_enabled?
  end

  supports :label_mapping

  def streaming_refresh_enabled?
    Settings.ems_refresh[emstype.to_sym]&.streaming_refresh
  end

  def allow_targeted_refresh?
    true
  end

  supports :metrics do
    _("No metrics endpoint has been added") unless metrics_endpoint_exists?
  end

  def metrics_endpoint_exists?
    endpoints.where(:role => METRICS_ROLES).exists?
  end

  def self.ems_type
    @ems_type ||= "kubernetes".freeze
  end

  def self.description
    @description ||= "Kubernetes".freeze
  end

  def self.raw_connect(hostname, port, options)
    kubernetes_connect(hostname, port, options)
  end

  def self.event_monitor_class
    ManageIQ::Providers::Kubernetes::ContainerManager::EventCatcher
  end

  def self.refresh_worker_class
    self::RefreshWorker
  end

  def self.display_name(number = 1)
    n_('Container Provider (Kubernetes)', 'Container Providers (Kubernetes)', number)
  end

  def self.default_port
    DEFAULT_PORT
  end

  LABEL_MAPPING_MODELS = %w[
    ContainerGroup
    ContainerProject
    ContainerNode
    ContainerReplicator
    ContainerRoute
    ContainerService
    ContainerBuild
  ].freeze

  def self.entities_for_label_mapping
    LABEL_MAPPING_MODELS.each_with_object({}) { |target_model, entity| entity[target_model] = target_model }
  end

  def self.label_mapping_prefix
    ems_type
  end

  def hostname_uniqueness_valid?
    return unless hostname_required?
    return unless hostname.present? # Presence is checked elsewhere
    # check uniqueness per provider type

    existing_providers = self.class.all - [self]
    existing_endpoints = existing_providers.map do |ems|
      next if ems.hostname.nil?

      "#{ems.hostname.downcase}:#{ems.port}"
    end

    errors.add(:hostname, N_("has to be unique per provider type")) if existing_endpoints.include?("#{hostname.downcase}:#{port}")
  end

  def self.params_for_create
    {
      :fields => [
        {
          :component => 'sub-form',
          :id        => 'endpoints-subform',
          :name      => 'endpoints-subform',
          :title     => _('Endpoints'),
          :fields    => [
            :component => 'tabs',
            :name      => 'tabs',
            :fields    => [
              {
                :component => 'tab-item',
                :id        => 'default-tab',
                :name      => 'default-tab',
                :title     => _('Default'),
                :fields    => [
                  {
                    :component              => 'validate-provider-credentials',
                    :id                     => 'authentications.default.valid',
                    :name                   => 'authentications.default.valid',
                    :skipSubmit             => true,
                    :isRequired             => true,
                    :validationDependencies => %w[type zone_id],
                    :fields                 => [
                      {
                        :component    => "select",
                        :id           => "endpoints.default.security_protocol",
                        :name         => "endpoints.default.security_protocol",
                        :label        => _("Security Protocol"),
                        :isRequired   => true,
                        :validate     => [{:type => "required"}],
                        :initialValue => 'ssl-with-validation',
                        :options      => [
                          {
                            :label => _("SSL"),
                            :value => "ssl-with-validation"
                          },
                          {
                            :label => _("SSL trusting custom CA"),
                            :value => "ssl-with-validation-custom-ca"
                          },
                          {
                            :label => _("SSL without validation"),
                            :value => "ssl-without-validation",
                          },
                        ]
                      },
                      {
                        :component  => "text-field",
                        :id         => "endpoints.default.hostname",
                        :name       => "endpoints.default.hostname",
                        :label      => _("Hostname (or IPv4 or IPv6 address)"),
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                      },
                      {
                        :component    => "text-field",
                        :id           => "endpoints.default.port",
                        :name         => "endpoints.default.port",
                        :label        => _("API Port"),
                        :type         => "number",
                        :initialValue => default_port,
                        :isRequired   => true,
                        :validate     => [{:type => "required"}],
                      },
                      {
                        :component  => "textarea",
                        :id         => "endpoints.default.certificate_authority",
                        :name       => "endpoints.default.certificate_authority",
                        :label      => _("Trusted CA Certificates"),
                        :rows       => 10,
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                        :condition  => {
                          :when => 'endpoints.default.security_protocol',
                          :is   => 'ssl-with-validation-custom-ca',
                        },
                      },
                      {
                        :component  => "password-field",
                        :id         => "authentications.bearer.auth_key",
                        :name       => "authentications.bearer.auth_key",
                        :label      => "Token",
                        :helperText => _('Note: If enabled, the Default, Metrics, and Alert Endpoints must be revalidated when adding or changing the token'),
                        :type       => "password",
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                      },
                    ]
                  }
                ]
              },
              {
                :component => 'tab-item',
                :id        => 'metrics-tab',
                :name      => 'metrics-tab',
                :title     => _('Metrics'),
                :fields    => [
                  {
                    :component    => 'protocol-selector',
                    :id           => 'metrics_selection',
                    :name         => 'metrics_selection',
                    :skipSubmit   => true,
                    :initialValue => 'none',
                    :label        => _('Type'),
                    :options      => [
                      {
                        :label => _('Disabled'),
                        :value => 'none',
                      },
                      {
                        :label => _('Prometheus'),
                        :value => 'prometheus',
                        :pivot => 'endpoints.prometheus.hostname',
                      },
                    ],
                  },
                  {
                    :component              => 'validate-provider-credentials',
                    :id                     => "authentications.prometheus.valid",
                    :name                   => "authentications.prometheus.valid",
                    :skipSubmit             => true,
                    :isRequired             => true,
                    :validationDependencies => %w[type zone_id metrics_selection authentications.bearer.auth_key],
                    :condition              => {
                      :when => "metrics_selection",
                      :is   => 'prometheus',
                    },
                    :fields                 => [
                      {
                        :component    => "select",
                        :id           => "endpoints.prometheus.security_protocol",
                        :name         => "endpoints.prometheus.security_protocol",
                        :label        => _("Security Protocol"),
                        :isRequired   => true,
                        :initialValue => 'ssl-with-validation',
                        :validate     => [{:type => "required"}],
                        :options      => [
                          {
                            :label => _("SSL"),
                            :value => "ssl-with-validation"
                          },
                          {
                            :label => _("SSL trusting custom CA"),
                            :value => "ssl-with-validation-custom-ca"
                          },
                          {
                            :label => _("SSL without validation"),
                            :value => "ssl-without-validation"
                          },
                        ]
                      },
                      {
                        :component  => "text-field",
                        :id         => "endpoints.prometheus.hostname",
                        :name       => "endpoints.prometheus.hostname",
                        :label      => _("Hostname (or IPv4 or IPv6 address)"),
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                        :inputAddon => {
                          :after => {
                            :fields => [
                              {
                                :component => 'input-addon-button-group',
                                :id        => 'detect-prometheus-group',
                                :name      => 'detect-prometheus-group',
                                :fields    => [
                                  {
                                    :component    => 'detect-button',
                                    :id           => 'detect-prometheus-button',
                                    :name         => 'detect-prometheus-button',
                                    :label        => _('Detect'),
                                    :dependencies => [
                                      'endpoints.default.hostname',
                                      'endpoints.default.port',
                                      'endpoints.default.security_protocol',
                                      'endpoints.default.certificate_authority',
                                      'authentications.bearer.auth_key',
                                    ],
                                    :target       => 'endpoints.prometheus',
                                  },
                                ],
                              }
                            ],
                          },
                        },
                      },
                      {
                        :component    => "text-field",
                        :id           => "endpoints.prometheus.port",
                        :name         => "endpoints.prometheus.port",
                        :label        => _("API Port"),
                        :type         => "number",
                        :initialValue => 443,
                        :isRequired   => true,
                        :validate     => [{:type => "required"}],
                      },
                      {
                        :component  => "textarea",
                        :id         => "endpoints.prometheus.certificate_authority",
                        :name       => "endpoints.prometheus.certificate_authority",
                        :label      => _("Trusted CA Certificates"),
                        :rows       => 10,
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                        :condition  => {
                          :when => 'endpoints.prometheus.security_protocol',
                          :is   => 'ssl-with-validation-custom-ca',
                        },
                      },
                    ]
                  }
                ]
              },
              {
                :component => 'tab-item',
                :id        => 'virtualization-tab',
                :name      => 'virtualization-tab',
                :title     => _('Virtualization'),
                :fields    => [
                  {
                    :component    => 'protocol-selector',
                    :id           => 'virtualization_selection',
                    :name         => 'virtualization_selection',
                    :skipSubmit   => true,
                    :initialValue => 'none',
                    :label        => _('Type'),
                    :options      => virtualization_options,
                  },
                  {
                    :component              => 'validate-provider-credentials',
                    :id                     => 'endpoints.virtualization.valid',
                    :name                   => 'endpoints.virtualization.valid',
                    :skipSubmit             => true,
                    :isRequired             => true,
                    :validationDependencies => %w[type zone_id virtualization_selection],
                    :condition              => {
                      :when => 'virtualization_selection',
                      :is   => 'kubevirt',
                    },
                    :fields                 => [
                      {
                        :component    => "select",
                        :id           => "endpoints.kubevirt.security_protocol",
                        :name         => "endpoints.kubevirt.security_protocol",
                        :label        => _("Security Protocol"),
                        :isRequired   => true,
                        :validate     => [{:type => "required"}],
                        :initialValue => 'ssl-with-validation',
                        :options      => [
                          {
                            :label => _("SSL"),
                            :value => "ssl-with-validation"
                          },
                          {
                            :label => _("SSL trusting custom CA"),
                            :value => "ssl-with-validation-custom-ca"
                          },
                          {
                            :label => _("SSL without validation"),
                            :value => "ssl-without-validation"
                          },
                        ]
                      },
                      {
                        :component  => "text-field",
                        :id         => "endpoints.kubevirt.hostname",
                        :name       => "endpoints.kubevirt.hostname",
                        :label      => _("Hostname (or IPv4 or IPv6 address)"),
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                        :inputAddon => {
                          :after => {
                            :fields => [
                              {
                                :component => 'input-addon-button-group',
                                :id        => 'detect-kubevirt-group',
                                :name      => 'detect-kubevirt-group',
                                :fields    => [
                                  {
                                    :component    => 'detect-button',
                                    :id           => 'detect-kubevirt-button',
                                    :name         => 'detect-kubevirt-button',
                                    :label        => _('Detect'),
                                    :dependencies => [
                                      'endpoints.default.hostname',
                                      'endpoints.default.port',
                                      'endpoints.default.security_protocol',
                                      'endpoints.default.certificate_authority',
                                      'authentications.bearer.auth_key',
                                    ],
                                    :target       => 'endpoints.kubevirt',
                                  },
                                ],
                              }
                            ],
                          },
                        },
                      },
                      {
                        :component    => "text-field",
                        :id           => "endpoints.kubevirt.port",
                        :name         => "endpoints.kubevirt.port",
                        :label        => _("API Port"),
                        :type         => "number",
                        :initialValue => default_port,
                        :isRequired   => true,
                        :validate     => [{:type => "required"}],
                      },
                      {
                        :component  => "textarea",
                        :id         => "endpoints.kubevirt.certificate_authority",
                        :name       => "endpoints.kubevirt.certificate_authority",
                        :label      => _("Trusted CA Certificates"),
                        :rows       => 10,
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                        :condition  => {
                          :when => 'endpoints.kubevirt.security_protocol',
                          :is   => 'ssl-with-validation-custom-ca',
                        },
                      },
                      {
                        :component  => "password-field",
                        :id         => "authentications.kubevirt.auth_key",
                        :name       => "authentications.kubevirt.auth_key",
                        :label      => "Token",
                        :type       => "password",
                        :isRequired => true,
                        :validate   => [{:type => "required"}],
                      },
                    ]
                  }
                ]
              }
            ]
          ]
        },
        {
          :component => 'sub-form',
          :id        => 'settings-subform',
          :name      => 'settings-subform',
          :title     => _('Settings'),
          :fields    => [
            :component => 'tabs',
            :name      => 'tabs',
            :fields    => [
              {
                :component => 'tab-item',
                :id        => 'proxy-tab',
                :name      => 'proxy-tab',
                :title     => _('Proxy'),
                :fields    => [
                  {
                    :component   => 'text-field',
                    :id          => 'options.proxy_settings.http_proxy',
                    :name        => 'options.proxy_settings.http_proxy',
                    :label       => _('HTTP Proxy'),
                    :helperText  => _('HTTP Proxy to connect ManageIQ to the provider. example: http://user:password@my_http_proxy'),
                    :placeholder => VMDB::Util.http_proxy_uri.to_s
                  }
                ],
              },
              {
                :component => 'tab-item',
                :id        => 'image-inspector-tab',
                :name      => 'image-inspector-tab',
                :title     => _('Image-Inspector'),
                :fields    => [
                  {
                    :component  => 'text-field',
                    :id         => 'options.image_inspector_options.http_proxy',
                    :name       => 'options.image_inspector_options.http_proxy',
                    :label      => _('HTTP Proxy'),
                    :helperText => _('HTTP Proxy to connect image inspector pods to the internet. example: http://user:password@my_http_proxy')
                  },
                  {
                    :component  => 'text-field',
                    :id         => 'options.image_inspector_options.https_proxy',
                    :name       => 'options.image_inspector_options.https_proxy',
                    :label      => _('HTTPS Proxy'),
                    :helperText => _('HTTPS Proxy to connect image inspector pods to the internet. example: https://user:password@my_https_proxy')
                  },
                  {
                    :component  => 'text-field',
                    :id         => 'options.image_inspector_options.no_proxy',
                    :name       => 'options.image_inspector_options.no_proxy',
                    :label      => _('No Proxy'),
                    :helperText => _("No Proxy lists urls that should'nt be sent to any proxy. example: my_file_server.org")
                  },
                  {
                    :component   => 'text-field',
                    :id          => 'options.image_inspector_options.repository',
                    :name        => 'options.image_inspector_options.repository',
                    :label       => _('Repository'),
                    :helperText  => _('Image-Inspector Repository. example: openshift/image-inspector'),
                    :placeholder => ::Settings.ems.ems_kubernetes.image_inspector_repository
                  },
                  {
                    :component   => 'text-field',
                    :id          => 'options.image_inspector_options.registry',
                    :name        => 'options.image_inspector_options.registry',
                    :label       => _('Registry'),
                    :helperText  => _('Registry to provide the image inspector repository. example: docker.io'),
                    :placeholder => ::Settings.ems.ems_kubernetes.image_inspector_registry
                  },
                  {
                    :component   => 'text-field',
                    :id          => 'options.image_inspector_options.image_tag',
                    :name        => 'options.image_inspector_options.image_tag',
                    :label       => _('Image Tag'),
                    :helperText  => _('Image-Inspector image tag. example: 2.1'),
                    :placeholder => ManageIQ::Providers::Kubernetes::ContainerManager::Scanning::Job::INSPECTOR_IMAGE_TAG
                  },
                  {
                    :component   => 'text-field',
                    :id          => 'options.image_inspector_options.cve_url',
                    :name        => 'options.image_inspector_options.cve_url',
                    :label       => _('CVE Location'),
                    :helperText  => _('Alternative URL path for the XCCDF file, where a com.redhat.rhsa-RHEL7.ds.xml.bz2 file is expected. example: http://my_file_server.example.org:3333/xccdf_files/'),
                    :placeholder => ::Settings.ems.ems_kubernetes.image_inspector_cve_url
                  },
                ],
              },
            ],
          ],
        },
      ],
    }
  end

  def self.virtualization_options
    [
      {
        :label => _('Disabled'),
        :value => 'none',
      },
      {
        :label => _('KubeVirt'),
        :value => 'kubevirt',
        :pivot => 'endpoints.kubevirt.hostname',
      },
    ]
  end

  def self.verify_credentials(args)
    endpoint_name = args.dig("endpoints").keys.first
    endpoint = args.dig("endpoints", endpoint_name)

    token = args.dig("authentications", "bearer", "auth_key") || args.dig("authentications", "kubevirt", "auth_key")
    token = ManageIQ::Password.try_decrypt(token)
    token ||= find(args["id"]).authentication_token(endpoint_name == 'kubevirt' ? 'kubevirt' : 'bearer') if args["id"]

    hostname, port = endpoint&.values_at("hostname", "port")

    options = {
      :bearer      => token,
      :ssl_options => {
        :verify_ssl => endpoint&.dig("security_protocol") == 'ssl-without-validation' ? OpenSSL::SSL::VERIFY_NONE : OpenSSL::SSL::VERIFY_PEER,
        :ca_file    => endpoint&.dig("certificate_authority")
      }
    }

    connection_rescue_block do
      case endpoint_name
      when 'default'
        verify_default_credentials(hostname, port, options)
      when 'kubevirt'
        verify_kubevirt_credentials(hostname, port, options)
      when 'hawkular'
        verify_hawkular_credentials(hostname, port, options)
      when 'prometheus'
        verify_prometheus_credentials(hostname, port, options)
      when 'prometheus_alerts'
        verify_prometheus_alerts_credentials(hostname, port, options)
      else
        raise MiqException::MiqInvalidCredentialsError, _("Unsupported endpoint")
      end
    end
  end

  def self.connection_rescue_block
    require "kubeclient"
    require "rest-client"
    yield
  rescue SocketError,
         Errno::ECONNREFUSED,
         RestClient::ResourceNotFound,
         RestClient::InternalServerError => err
    raise MiqException::MiqUnreachableError, err.message
  rescue RestClient::Unauthorized, Kubeclient::HttpError => err
    raise MiqException::MiqInvalidCredentialsError, err.message
  end

  def self.create_from_params(params, endpoints, authentications)
    bearer = authentications.find { |authentication| authentication['authtype'] == 'bearer' }

    # Replicate the bearer authentication for all endpoints, except for default and kubevirt
    endpoints.each do |endpoint|
      next if %w[default kubevirt].include?(endpoint['role'])

      authentications << bearer.merge('authtype' => endpoint['role'])
    end

    super(params, endpoints, authentications)
  end

  def self.raw_api_endpoint(hostname, port, path = '')
    URI::HTTPS.build(:host => hostname, :port => port.presence.try(:to_i), :path => path)
  end

  def self.kubernetes_connect(hostname, port, options)
    require 'kubeclient'

    conn = Kubeclient::Client.new(
      raw_api_endpoint(hostname, port, options[:path]),
      options[:version] || kubernetes_version,
      :ssl_options    => Kubeclient::Client::DEFAULT_SSL_OPTIONS.merge(options[:ssl_options] || {}),
      :auth_options   => kubernetes_auth_options(options),
      :http_proxy_uri => options[:http_proxy] || VMDB::Util.http_proxy_uri,
      :timeouts       => {
        :open => Settings.ems.ems_kubernetes.open_timeout.to_f_with_method,
        :read => Settings.ems.ems_kubernetes.read_timeout.to_f_with_method
      }
    )

    # Test the API endpoint at connect time to prevent exception being raised
    # on first method call
    conn.discover

    conn
  end

  def self.kubernetes_auth_options(options)
    auth_options = {}
    if options[:username] && options[:password]
      auth_options[:username] = options[:username]
      auth_options[:password] = options[:password]
    end
    auth_options[:bearer_token] = options[:bearer] if options[:bearer]
    auth_options
  end

  def self.kubernetes_version
    'v1'
  end

  def self.kubernetes_service_catalog_connect(hostname, port, options)
    options = {:path => '/apis/servicecatalog.k8s.io', :version => service_catalog_api_version}.merge(options)
    kubernetes_connect(hostname, port, options)
  end

  def self.service_catalog_api_version
    'v1beta1'
  end

  def self.prometheus_connect(hostname, port, options)
    require 'prometheus/api_client'

    uri         = raw_api_endpoint(hostname, port).to_s
    credentials = {:token => options[:bearer]}
    ssl_options = options[:ssl_options] || {:verify_ssl => OpenSSL::SSL::VERIFY_NONE}

    http_proxy_uri = options[:http_proxy] || VMDB::Util.http_proxy_uri.to_s
    prometheus_options = {
      :http_proxy_uri => http_proxy_uri.presence,
      :verify_ssl     => ssl_options[:verify_ssl],
      :ssl_cert_store => ssl_options[:ca_file],
    }

    Prometheus::ApiClient.client(:url => uri, :credentials => credentials, :options => prometheus_options)
  end

  def self.verify_k8s_credentials(kube)
    !!kube&.api_valid? && !kube.get_namespaces(:limit => 1).nil?
  end

  def self.verify_default_credentials(hostname, port, options)
    verify_k8s_credentials(kubernetes_connect(hostname, port, options))
  end

  def self.verify_prometheus_credentials(hostname, port, options)
    !!prometheus_connect(hostname, port, options)&.query(:query => "ALL")&.kind_of?(Hash)
  end

  def self.kubevirt_connect(hostname, port, options)
    ManageIQ::Providers::Kubevirt::InfraManager.raw_connect(:server => hostname, :port => port, :token => options[:bearer])
  end

  def self.verify_kubevirt_credentials(hostname, port, options)
    ManageIQ::Providers::Kubevirt::InfraManager.verify_credentials(
      "endpoints" => {
        "default" => {
          "server" => hostname,
          "port"   => port,
          "token"  => options[:bearer]
        }
      }
    )
  end

  PERF_ROLLUP_CHILDREN = [:container_nodes]

  def edit_with_params(params, endpoints, authentications)
    bearer = authentications.find { |authentication| authentication['authtype'] == 'bearer' }
    kubevirt = authentications.find { |authentication| authentication['authtype'] == 'kubevirt' }
    # As the authentication is token-only, no data is being submitted if there's no change as we never send
    # down the password to the client. This would cause the deletion of the untouched authentications in the
    # super() below. In order to prevent this, the authentications are set to a dummy value if the related
    # endpoint exists among the submitted data.
    endpoints.each do |endpoint|
      case endpoint['role']
      when 'default' # The default endpoint is paired with the bearer authentication
        authentications << {'authtype' => 'bearer'} unless bearer
      when 'kubevirt' # Kubevirt has its own authentication, no need for replication
        authentications << {'authtype' => 'kubevirt'} unless kubevirt
      else # Replicate the bearer authentication for any other endpoints
        auth_key = bearer&.fetch('auth_key', authentication_token)
        authentications << {'authtype' => endpoint['role']}.reverse_merge(:auth_key => auth_key)
      end
    end

    super(params, endpoints, authentications)
  end

  def verify_default_credentials(options)
    options[:service] ||= "kubernetes"
    with_provider_connection(options) { |kube| self.class.verify_k8s_credentials(kube) }
  end

  def verify_prometheus_credentials
    client = ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusClient.new(self)
    client.prometheus_try_connect
  end

  def verify_kubevirt_credentials
    ensure_infra_manager
    options = {
      :token => authentication_token(:kubevirt),
    }
    infra_manager.verify_credentials(:kubevirt, options)
    infra_manager.verify_virt_supported(options)
  end

  def api_endpoint
    self.class.raw_api_endpoint(hostname, port)
  end

  def verify_ssl_mode(endpoint = default_endpoint)
    return OpenSSL::SSL::VERIFY_PEER if endpoint.nil? # secure by default

    case endpoint.security_protocol
    when nil, ''
      # Previously providers didn't set security_protocol, defaulted to
      # verify_ssl == 1 (VERIFY_PEER) which wasn't enforced but now is.
      # However, if they explicitly set verify_ssl == 0, we'll respect that.
      endpoint.verify_ssl? ? OpenSSL::SSL::VERIFY_PEER : OpenSSL::SSL::VERIFY_NONE
    when 'ssl-without-validation'
      OpenSSL::SSL::VERIFY_NONE
    else # 'ssl-with-validation', 'ssl-with-validation-custom-ca', secure by default with unexpected values.
      OpenSSL::SSL::VERIFY_PEER
    end
  end

  def ssl_cert_store(endpoint = default_endpoint)
    # Given missing (nil) endpoint, return nil meaning use system CA bundle
    endpoint.try(:ssl_cert_store)
  end

  def connect(options = {})
    effective_options = connect_options(options)

    self.class.raw_connect(effective_options[:hostname], effective_options[:port], effective_options)
  end

  def connect_options(options = {})
    options.merge(
      :hostname    => options[:hostname] || address,
      :port        => options[:port] || port,
      :username    => options[:username] || authentication_userid(options[:auth_type]),
      :password    => options[:password] || authentication_password(options[:auth_type]),
      :bearer      => options[:bearer] || authentication_token(options[:auth_type] || 'bearer'),
      :http_proxy  => self.options ? self.options.fetch_path(:proxy_settings, :http_proxy) : nil,
      :ssl_options => options[:ssl_options] || {
        :verify_ssl => verify_ssl_mode,
        :cert_store => ssl_cert_store
      }
    )
  end

  def authentications_to_validate
    at = [:bearer]
    at << :prometheus if has_authentication_type?(:prometheus)
    at << :prometheus_alerts if has_authentication_type?(:prometheus_alerts)
    at << :kubevirt if has_authentication_type?(:kubevirt)
    at
  end

  def required_credential_fields(_type)
    [:auth_key]
  end

  def supported_auth_attributes
    %w(userid password auth_key)
  end

  def verify_credentials(auth_type = nil, options = {})
    options = options.merge(:auth_type => auth_type)

    self.class.connection_rescue_block do
      case options[:auth_type].to_s
      when "prometheus"
        verify_prometheus_credentials
      when "prometheus_alerts"
        verify_prometheus_alerts_credentials
      when "kubevirt"
        verify_kubevirt_credentials
      else
        verify_default_credentials(options)
      end
    end
  end

  def after_update_authentication
    super
    stop_refresh_worker_queue_on_credential_change
  end

  def ensure_authentications_record
    return if authentications.present?
    update_authentication(:default => {:userid => "_", :save => false})
  end

  def supported_auth_types
    %w[default password bearer prometheus prometheus_alerts kubevirt]
  end

  def default_authentication_type
    :bearer
  end

  def scan_job_create(entity, userid)
    check_policy_prevent(:request_containerimage_scan, entity, userid, :raw_scan_job_create)
  end

  def raw_scan_job_create(target_class, target_id = nil, userid = nil, target_name = nil)
    raise MiqException::Error, _("target_class must be a class not an instance") if target_class.kind_of?(ContainerImage)
    ManageIQ::Providers::Kubernetes::ContainerManager::Scanning::Job.create_job(
      :userid          => userid,
      :name            => "Container Image Analysis: '#{target_name}'",
      :target_class    => target_class,
      :target_id       => target_id,
      :zone            => my_zone,
      :miq_server_host => MiqServer.my_server.hostname,
      :miq_server_guid => MiqServer.my_server.guid,
      :ems_id          => id,
    )
  end

  # policy_event: the event sent to automate for policy resolution
  # cb_method:    the MiqQueue callback method along with the parameters that is called
  #               when automate process is done and the event is not prevented to proceed by policy
  def check_policy_prevent(policy_event, event_target, userid, cb_method)
    cb = {
      :class_name  => self.class.to_s,
      :instance_id => id,
      :method_name => :check_policy_prevent_callback,
      :args        => [cb_method, event_target.class.name, event_target.id, userid, event_target.name],
      :server_guid => MiqServer.my_guid
    }
    enforce_policy(event_target, policy_event, {}, { :miq_callback => cb }) unless policy_event.nil?
  end

  def check_policy_prevent_callback(*action, _status, _message, result)
    prevented = false
    if result.kind_of?(MiqAeEngine::MiqAeWorkspaceRuntime)

      event = result.get_obj_from_path("/")['event_stream']
      data  = event.attributes["full_data"]
      prevented = data.fetch_path(:policy, :prevented) if data
    end
    prevented ? _log.info(event.attributes["message"].to_s) : send(*action)
  end

  def enforce_policy(event_target, event, inputs = {}, options = {})
    MiqEvent.raise_evm_event(event_target, event, inputs, options)
  end

  SCAN_CONTENT_PATH = '/api/v1/content'

  def scan_entity_create(scan_data)
    client = ext_management_system.connect(:service => 'kubernetes')
    pod_proxy = client.proxy_url(:pod,
                                 scan_data[:pod_name],
                                 scan_data[:pod_port],
                                 scan_data[:pod_namespace])
    nethttp_options = {
      :use_ssl     => true,
      :verify_mode => verify_ssl_mode,
      :cert_store  => ssl_cert_store,
    }
    MiqContainerGroup.new(pod_proxy + SCAN_CONTENT_PATH,
                          nethttp_options,
                          client.headers.stringify_keys,
                          scan_data[:guest_os])
  end

  def annotate(provider_entity_name, ems_indentifier, annotations, container_project_name = nil)
    with_provider_connection do |conn|
      conn.send(
        "patch_#{provider_entity_name}".to_sym,
        ems_indentifier,
        {"metadata" => {"annotations" => annotations}},
        container_project_name # nil is ok for non namespaced entities (e.g images)
      )
    end
  end

  def evaluate_alert(_alert_id, _event)
    # currently only EmsEvents from Prometheus are tested for node alerts,
    # and these should automatically be translated to alerts.
    true
  end

  def queue_metrics_capture
    self.perf_capture_object.perf_capture_all_queue
  end
end
