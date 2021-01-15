class ManageIQ::Providers::Kubernetes::ContainerManager::KubernetesEventMonitor
  include Vmdb::Logging

  def initialize(ems)
    @ems = ems
  end

  def inventory
    # :service is required to handle also the case where @ems is Openshift
    @inventory ||= @ems.connect(:service => ManageIQ::Providers::Kubernetes::ContainerManager.ems_type)
  end

  def watcher(version = nil)
    @watcher ||= inventory.watch_events(version)
  end

  def start
    @inventory = nil
    @watcher = nil
  end

  def stop
    watcher.finish
  end

  def each
    # At the moment we don't persist the last resourceVersion seen by the
    # inventory, this means that for now we take the last version and we
    # request events starting from there. This assumes that on reconnection
    # we should trigger a full inventory poll.
    # TODO: persist resourceVersion and gather only the relevant events
    # that may have been missed.
    version = inventory.get_events.resourceVersion
    watcher(version).each do |notice|
      yield notice
    end
  rescue EOFError => err
    _log.info("Monitoring connection closed #{err}")
  end
end
