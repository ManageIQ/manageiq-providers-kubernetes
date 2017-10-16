class ManageIQ::Providers::Kubernetes::MonitoringManager::EventCatcher::Stream
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
      yield(fetch)
    end
  rescue EOFError => err
    $cn_monitoring_log.info("Monitoring connection closed #{err}")
  end

  def fetch
    unless @current_generation
      @current_generation, @current_index = last_position
    end
    $cn_monitoring_log.info("Fetching alerts. Generation: [#{@current_generation}/#{@current_index}]")

    response = @ems.connect.get do |req|
      req.params['generationID'] = @current_generation
      req.params['fromIndex'] = @current_index
    end
    # {
    #   "generationID":"323e0863-f501-4896-b7dc-353cf863597d",
    #   "messages":[
    #   ...
    #   ]
    # }
    alert_list = response.body
    alerts = []
    @current_generation = alert_list["generationID"]
    return alerts if alert_list['messages'].blank?
    alert_list["messages"].each do |message|
      @current_index = message['index']
      unless message.fetch_path("data", "commonAnnotations", "miqTarget") == 'ContainerNode'
        $cn_monitoring_log.info("Skipping alert due to missing annotation")
        next
      end
      message["data"]["alerts"].each_with_index do |alert, i|
        alert['generationID'] = @current_generation
        alert['index'] = @current_index
        alert['timestamp'] = timestamp_indent(alert, i)
        alerts << alert
      end
      @current_index += 1
    end
    $cn_monitoring_log.info("[#{alerts.size}] new alerts. New generation: [#{@current_generation}/#{@current_index}]")
    $cn_monitoring_log.debug(alerts)
    alerts
  end

  def timestamp_indent(alert, indent)
    # This is currently needed due to a uniqueness constraint on ems events
    # see https://github.com/ManageIQ/manageiq/pull/15719
    # Prometheus alert timestamp equals the evaluation cycle start timestamp
    # We are adding an artificial indent of the lest significant bit since several alerts
    # for different entities or from different alert definitions are likely to have the same timestamp
    timestamp = alert["status"] == 'resolved' ? alert["endsAt"] : alert["startsAt"]
    Time.zone.at((Time.parse(timestamp).to_f + (0.000001 * indent)))
  end

  def last_position
    last_event = @ems.parent_manager.ems_events.last || OpenStruct.new(:full_data => {})
    last_index = last_event.full_data['index']
    [
      last_event.full_data['generationID'].to_s,
      last_index ? last_index + 1 : 0
    ]
  end
end
