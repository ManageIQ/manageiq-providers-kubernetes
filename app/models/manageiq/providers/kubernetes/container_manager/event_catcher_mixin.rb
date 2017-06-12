module ManageIQ::Providers::Kubernetes::ContainerManager::EventCatcherMixin
  extend ActiveSupport::Concern

  class PrometheusEventMonitor
    def initialize(ems)
      @ems = ems
    end

    def start
      @collecting_events = true
    end

    def stop
      @collecting_events = false
    end

    def each_batch
      while @collecting_events
        yield fetch
      end
      # version = inventory.get_events.resourceVersion
      # watcher(version).each do |notice|
      #   yield notice
      # end
    rescue EOFError => err
      $kube_log.info("Monitoring connection closed #{err}")
    end

    def fetch
      endpoint = @ems.connection_configurations.hawkular.try(:endpoint)
      url = "http://#{endpoint.hostname}/api/v1/alerts"
      conn = Faraday.new(:url => url) do |faraday|
        faraday.adapter Faraday.default_adapter
        faraday.response :json
      end

      response = conn.get
      body = response.body
      events = body["data"].select { |alert| alert["labels"]["job"] == 'kubernetes-nodes' }
      events
    end
  end

  def event_monitor_handle
    @event_monitor_handle ||= PrometheusEventMonitor.new(@ems)
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
    event_monitor_handle.each_batch do |event|
      @queue.enq event
      # TODO: mark all events not retrieved as resolved
      sleep_poll_normal
    end

  ensure
    reset_event_monitor_handle
  end

  def queue_event(event)
    event_hash = extract_event_data(event)
    _log.info "#{log_prefix} Queuing event [#{event_hash}]"
    EmsEvent.add_queue('add', @cfg[:ems_id], event_hash)
  end

  # Returns hash, or nil if event should be discarded.
  def extract_event_data(event)
    annotations, labels = event["annotations"], event["labels"]
    started = Time.zone.at(Time.parse(event["startsAt"])) # 2017-06-02T18:55:37.805Z
    instance = ContainerNode.find_by(:name => labels["instance"])
    {
      :ems_id              => @cfg[:ems_id],
      :source              => 'DATAWAREHOUSE',
      :timestamp           => started,
      :event_type          => 'datawarehouse_alert',
      :target_type         => instance.class.name,
      :target_id           => instance.id,
      :container_node_id   => instance.id,
      :container_node_name => instance.name,
      :message             => annotations["summary"],
      :full_data           => event.to_h
    }
  end
end
