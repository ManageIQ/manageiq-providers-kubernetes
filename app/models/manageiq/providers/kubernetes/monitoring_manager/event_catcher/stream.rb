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
    #     "index": 1,
    #     "timestamp": "2017-10-17T08:30:00.466775417Z",
    #     "data": {
    #       "alerts": [
    #         ...
    #       ]
    #     }
    #   ...
    #   ]
    # }
    alert_list = response.body
    alerts = []
    @current_generation = alert_list["generationID"]
    return alerts if alert_list['messages'].blank?
    alert_list["messages"].each do |message|
      @current_index = message['index']
      message["data"]["alerts"].each do |alert|
        if alert_for_miq?(alert)
          alerts << process_alert!(alert, @current_generation, @current_index)
        else
          $cn_monitoring_log.info("Skipping alert due to missing annotation or unexpected target")
        end
      end
      @current_index += 1
    end
    $cn_monitoring_log.info("[#{alerts.size}] new alerts. New generation: [#{@current_generation}/#{@current_index}]")
    $cn_monitoring_log.debug(alerts)
    alerts
  end

  def process_alert!(alert, generation, group_index)
    alert['generationID'] = generation
    alert['index'] = group_index
    alert
  end

  def alert_for_miq?(alert)
    alert.fetch_path("annotations", "miqIgnore").to_s.downcase != "true"
  end

  def last_position
    last_event = @ems.parent_manager.ems_events.where(:source => "DATAWAREHOUSE").last
    last_event ||= OpenStruct.new(:full_data => {})
    last_index = last_event.full_data['index']
    [
      last_event.full_data['generationID'].to_s,
      last_index ? last_index + 1 : 0
    ]
  end
end
