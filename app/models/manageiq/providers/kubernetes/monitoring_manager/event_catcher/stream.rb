class ManageIQ::Providers::Kubernetes::MonitoringManager::EventCatcher::Stream
  include Vmdb::Logging

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
    _log.info("Monitoring connection closed #{err}")
  end

  def fetch
    unless @current_generation
      @current_generation, @current_index = last_position
    end
    _log.info("Fetching alerts. Generation: [#{@current_generation}/#{@current_index}]")

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
    alert_list = @ems.connect.get(:generation_id => @current_generation, :from_index => @current_index)
    alerts = []
    alert_list = JSON.parse(alert_list) if alert_list.kind_of?(String)
    @current_generation = alert_list["generationID"]
    return alerts if alert_list['messages'].blank?
    alert_list["messages"].each do |message|
      @current_index = message['index']
      message["data"]["alerts"].each do |alert|
        if alert_for_miq?(alert)
          alerts << process_alert!(alert, @current_generation, @current_index)
        else
          _log.info("Skipping alert due to missing annotation or unexpected target")
        end
      end
      @current_index += 1
    end
    _log.info("[#{alerts.size}] new alerts. New generation: [#{@current_generation}/#{@current_index}]")
    _log.debug(alerts)
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
