module ManageIQ::Providers::Kubernetes::ContainerManager::EventCatcherMixin
  extend ActiveSupport::Concern

  # Kinds not modelled in ManageIQ inventory; dropped before parsing regardless
  # of reason. Not operator-configurable — there is no valid use-case for them.
  DISABLED_KINDS = %w[Endpoints EndpointSlice Lease].freeze

  def event_monitor_handle
    @event_monitor_handle ||= ManageIQ::Providers::Kubernetes::ContainerManager::KubernetesEventMonitor.new(@ems)
  end

  def reset_event_monitor_handle
    @event_monitor_handle = nil
  end

  def stop_event_monitor
    @event_monitor_handle.stop unless @event_monitor_handle.nil?
  rescue => err
    _log.error("#{log_prefix} Event Monitor error [#{err.message}]")
    _log.error("#{log_prefix} Error details: [#{err.details}]")
    _log.log_backtrace(err)
  ensure
    reset_event_monitor_handle
  end

  def monitor_events
    event_monitor_handle.start
    event_monitor_running
    # TODO: since event_monitor_handle is returning only events that
    # are generated starting from this moment we need to pull the
    # entire # inventory to make sure that it's up-to-date.
    event_monitor_handle.each do |event|
      # Sleeping here is not necessary because the events are delivered
      # asynchronously when available.
      @queue.enq event
    end
  ensure
    reset_event_monitor_handle
  end

  def queue_event(event)
    event_data = extract_event_data(event)
    if !event_valid?(event_data)
      _log.info "#{log_prefix} Skipping invalid event [#{event_data[:event_type]}]"
      return
    end

    _log.info "#{log_prefix} Queuing event [#{event_data}]"
    event_hash = ManageIQ::Providers::Kubernetes::ContainerManager::EventParser.event_to_hash(event_data, @cfg[:ems_id])
    EmsEvent.add_queue('add', @cfg[:ems_id], event_hash)
  end

  def filtered?(event)
    kind = event.object.involvedObject.kind
    return true if DISABLED_KINDS.include?(kind)

    event_data = extract_event_data(event)
    filtered_events.include?(event_data[:event_type])
  end

  # Returns hash, or nil if event should be discarded.
  def extract_event_data(event)
    event_data = {
      :timestamp => event.object.lastTimestamp || event.object.eventTime,
      :kind      => event.object.involvedObject.kind,
      :name      => event.object.involvedObject.name,
      :namespace => event.object.involvedObject.namespace,
      :reason    => event.object.reason,
      :message   => event.object.message,
      :uid       => event.object.involvedObject.uid,
      :event_uid => event.object.metadata.uid,
    }

    unless event.object.involvedObject.fieldPath.nil?
      event_data[:fieldpath] = event.object.involvedObject.fieldPath
    end

    event_type_prefix = event_data[:kind].upcase

    # Handle event data for specific entities
    case event_data[:kind]
    when 'Node'
      event_data[:container_node_name] = event_data[:name]
    when 'Pod'
      /^spec.containers{(?<container_name>.*)}$/ =~ event_data[:fieldpath]
      unless container_name.nil?
        event_data[:container_name] = container_name
      end
      event_data[:container_group_name] = event_data[:name]
      event_data[:container_namespace] = event_data[:namespace]
    # TODO: ReplicationController is deprecated in favour of ReplicaSet/Deployment;
    when 'ReplicationController'
      event_type_prefix = "REPLICATOR"
      event_data[:container_replicator_name] = event_data[:name]
      event_data[:container_namespace] = event_data[:namespace]
    when 'ReplicaSet', 'Deployment', 'StatefulSet', 'DaemonSet', 'Job', 'CronJob'
      event_data[:container_namespace] = event_data[:namespace]
    end

    event_data[:event_type] = "#{event_type_prefix}_#{event_data[:reason].upcase}"

    event_data
  end

  def event_valid?(event_data)
    # If there is no timestamp we cannot properly handle the event
    return false if event_data[:timestamp].nil?

    true
  end

  private

  def worker_options
    options = super
    ems_type = @ems.class.ems_type
    options[:settings] = worker_settings.merge(
      :ems => {
        "ems_#{ems_type}" => ::Settings.ems["ems_#{ems_type}"]&.to_hash
      }
    )
    # `.attributes` returns raw (encrypted) column values; decrypt each credential
    # field here so the non-Rails worker subprocess receives usable plaintext.
    options[:ems].each do |manager|
      manager["authentications"].each do |authentication|
        auth_record = Authentication.find(authentication["id"])
        authentication["password"] = auth_record.password
        authentication["auth_key"] = auth_record.auth_key
      end
    end
    options
  end
end
