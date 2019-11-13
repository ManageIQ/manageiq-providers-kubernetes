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

  def self.raw_connect(hostname, port, options)
    kubernetes_connect(hostname, port, options)
  end

  def self.event_monitor_class
    ManageIQ::Providers::Kubernetes::ContainerManager::EventCatcher
  end

  def self.display_name(number = 1)
    n_('Container Provider (Kubernetes)', 'Container Providers (Kubernetes)', number)
  end

  def self.default_port
    DEFAULT_PORT
  end
end
