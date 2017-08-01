module ManageIQ::Providers::Kubernetes::MonitoringManager::EventCatcher::RunnerMixin
  extend ActiveSupport::Concern

  # This module is shared between:
  # - Kubernetes::MonitoringManager::EventCatcher
  # - Openshift::MonitoringManager::EventCatcher

  def event_monitor_handle
    @event_monitor_handle ||= ManageIQ::Providers::Kubernetes::MonitoringManager::EventCatcher::Stream.new(@ems)
  end

  def reset_event_monitor_handle
    @event_monitor_handle = nil
  end

  def stop_event_monitor
    @event_monitor_handle.stop unless @event_monitor_handle.nil?
  rescue => err
    $cn_monitoring_log.error("Event Monitor error [#{err.message}]")
    $cn_monitoring_log.error("Error details: [#{err.details}]")
    $cn_monitoring_log.log_backtrace(err)
  ensure
    reset_event_monitor_handle
  end

  def monitor_events
    $cn_monitoring_log.info("[#{self.class.name}] Event Monitor started")
    @target_ems_id = @ems.parent_manager.id
    event_monitor_handle.start
    event_monitor_running
    event_monitor_handle.each_batch do |events|
      @queue.enq(events) unless events.blank?
      sleep_poll_normal
    end
  ensure
    reset_event_monitor_handle
  end

  def queue_event(event)
    event_hash = extract_event_data(event)
    if event_hash
      $cn_monitoring_log.info("Queuing event [#{event_hash}]")
      EmsEvent.add_queue("add", @target_ems_id, event_hash)
    end
  end

  def extract_event_data(event)
    # EXAMPLE:
    #
    # {
    #     "annotations": {
    #         "message": "Node ocp-compute01.10.35.48.236.nip.io is down",
    #         "severity": "HIGH",
    #         "source": "ManageIQ",
    #         "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
    #     },
    #     "endsAt": "0001-01-01T00:00:00Z",
    #     "generatorURL": "http://prometheus-4018548653-w3str:9090/graph?g0.expr=container_fs_usage_bytes%7Bcontainer_name%3D%22%22%2Cdevice%3D%22%2Fdev%2Fmapper%2Fvg0-lv_root%22%7D+%3E+4e%2B07&g0.tab=0",
    #     "labels": {
    #         "alertname": "Node down",
    #         "beta_kubernetes_io_arch": "amd64",
    #         "beta_kubernetes_io_os": "linux",
    #         "device": "/dev/mapper/vg0-lv_root",
    #         "id": "/",
    #         "instance": "ocp-compute01.10.35.48.236.nip.io",
    #         "job": "kubernetes-nodes",
    #         "kubernetes_io_hostname": "ocp-compute01.10.35.48.236.nip.io",
    #         "region": "primary",
    #         "zone": "default"
    #     },
    #     "startsAt": "2017-07-17T12:18:00.457154718Z",
    #     "status": "firing",
    #     "generationID" : "323e0863-f501-4896-b7dc-353cf863597d", # Added in stream
    #     "index": 1, # Added in stream
    # },
    event = event.dup

    annotations = event["annotations"]
    event[:url] = annotations["url"]
    event[:severity] = parse_severity(annotations["severity"])
    labels = event["labels"]
    event[:ems_ref] = incident_identifier(event, labels, annotations)
    event[:resolved] = event["status"] == "resolved"
    timestamp = event["timestamp"]

    target = find_target(labels)
    {
      :ems_id              => @cfg[:ems_id],
      :source              => "DATAWAREHOUSE",
      :timestamp           => timestamp,
      :event_type          => "datawarehouse_alert",
      :target_type         => target.class.name,
      :target_id           => target.id,
      :container_node_id   => target.id,
      :container_node_name => target.name,
      :message             => annotations["message"],
      :full_data           => event.to_h
    }
  end

  def find_target(labels)
    instance = ContainerNode.find_by(:name => labels["instance"], :ems_id => @target_ems_id)
    $cn_monitoring_log.error("Could not find alert target from labels: [#{labels}]") unless instance
    instance
  end

  def parse_severity(severity)
    MiqAlertStatus::SEVERITY_LEVELS.find { |x| x == severity.to_s.downcase } || "error"
  end

  def incident_identifier(event, labels, annotations)
    # When event b resolves event a, they both have the same startAt.
    # Labels are added to avoid having two incidents starting at the same time.
    Digest::SHA256.hexdigest(
      [event["startsAt"], annotations["url"], labels["instance"], labels["alertname"]].join('|')
    )
  end
end
