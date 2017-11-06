class ManageIQ::Providers::Kubernetes::MonitoringManager::EventCatcher::Stream
  def initialize(ems)
    @ems = ems
    @current_generation = nil
    @open_incident = nil
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
    check_state
    $cn_monitoring_log.info("Fetching alerts. Generation: [#{@current_generation}/#{@current_index}]")
    alert_list, error = poll_messages
    return [error] if error

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
    alerts = []

    if collection_incident_ongoing?
      alerts << resolve_collection_incident
      $cn_monitoring_log.info("[#{@ems.name}] collection problem resolved")
    end

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

  def check_state
    unless @current_generation # first run of worker, check if there is a position from previous run
      @current_generation, @current_index = last_position
    end
    unless @open_incident
      @open_incident = incident_custom_attribute
    end
  end

  def poll_messages
    response = @ems.connect.get(:generation_id => @current_generation, :from_index => @current_index)
    [response, nil]
  rescue Faraday::ClientError => err
    if collection_incident_ongoing?
      raise
    else
      $cn_monitoring_log.error("[#{@ems.name}] collection problem initiated")
      $cn_monitoring_log.error(err)
      [nil, initiate_collection_incident]
    end
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

  def collection_incident_ongoing?
    !@open_incident.value.nil?
  end

  def initiate_collection_incident
    @open_incident.update_attributes(:value => Time.zone.now)
    incident_event(@open_incident.value, true)
  end

  #
  # Emit a simulated Prometheus EmsEvent that can trigger an alert
  #
  def resolve_collection_incident
    initiation_time = @open_incident.value
    @open_incident.update_attributes(:value => nil)
    incident_event(initiation_time, false)
  end

  #
  # @returns Emit a simulated Prometheus EmsEvent that can trigger an alert
  #
  def incident_event(incident_start, firing)
    {
      "annotations"  => {
        "url"       => "www.example.com",
        "severity"  => "error",
        "miqTarget" => "ExtManagementSystem",
        "message"   => "Event Collection Problem",
        "UUID"      => "bde8a18c-913c-4b15-ba55-a1ca49b6674f",
      },
      "labels"       => {},
      "startsAt"     => incident_start,
      "status"       => firing ? "firing" : "resolved",
      "generationID" => @current_generation,
      "index"        => @current_index,
    }
  end

  def incident_custom_attribute
    CustomAttribute.find_or_create_by(
      :section     => "event_stream_state",
      :name        => "active_incident_start_date",
      :description => "Error in prometheus collection",
      :resource    => @ems,
      :source      => "ManageIQ::Providers::Kubernetes::MonitoringManager::EventCatcher::Stream",
    )
  end
end
