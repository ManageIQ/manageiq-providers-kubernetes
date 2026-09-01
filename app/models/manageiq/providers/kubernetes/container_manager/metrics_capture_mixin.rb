module ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCaptureMixin
  class CollectionFailure < RuntimeError; end
  class NoMetricsFoundError < RuntimeError; end

  class TargetValidationError < RuntimeError
    def log_severity
      :error
    end
  end

  class TargetValidationWarning < RuntimeError
    def log_severity
      :warn
    end
  end

  INTERVAL = 60.seconds

  VIM_STYLE_COUNTERS = {
    "cpu_usage_rate_average"     => {
      :counter_key           => "cpu_usage_rate_average",
      :instance              => "",
      :capture_interval      => INTERVAL.to_s,
      :precision             => 1,
      :rollup                => "average",
      :unit_key              => "percent",
      :capture_interval_name => "realtime"
    },
    "mem_usage_absolute_average" => {
      :counter_key           => "mem_usage_absolute_average",
      :instance              => "",
      :capture_interval      => INTERVAL.to_s,
      :precision             => 1,
      :rollup                => "average",
      :unit_key              => "percent",
      :capture_interval_name => "realtime"
    },
    "net_usage_rate_average"     => {
      :counter_key           => "net_usage_rate_average",
      :instance              => "",
      :capture_interval      => INTERVAL.to_s,
      :precision             => 1,
      :rollup                => "average",
      :unit_key              => "kilobytespersecond",
      :capture_interval_name => "realtime"
    }
  }

  def prometheus_capture_context(target, start_time, end_time)
    PrometheusCaptureContext.new(target, start_time, end_time, INTERVAL)
  end

  def metrics_connection(ems)
    ems.connection_configurations.prometheus
  end

  def metrics_connection_valid?(ems)
    metrics_connection(ems)&.authentication&.status == "Valid"
  end

  def verify_metrics_connection!(ems)
    raise TargetValidationError, "no provider for #{target_name}" if ems.nil?

    raise TargetValidationWarning, "no metrics endpoint found for #{target_name}" if metrics_connection(ems).nil?
    raise TargetValidationWarning, "metrics authentication isn't valid for #{target_name}" unless metrics_connection_valid?(ems)
  end

  def build_capture_context!(ems, target, start_time, end_time)
    verify_metrics_connection!(ems)
    # make start_time align to minutes
    start_time = start_time.beginning_of_minute

    context = prometheus_capture_context(target, start_time, end_time)
    raise TargetValidationWarning, "no metrics endpoint found for #{target_name}" if context.nil?

    context
  end

  def perf_collect_metrics(interval_name, start_time = nil, end_time = nil)
    raise "No EMS defined" if target.ext_management_system.nil?

    start_time ||= 15.minutes.ago.beginning_of_minute.utc
    ems = target.ext_management_system

    _log.info("Collecting metrics for #{target_name} [#{interval_name}] [#{start_time}] [#{end_time}]")

    begin
      context = build_capture_context!(ems, target, start_time, end_time)
    rescue TargetValidationError, TargetValidationWarning => e
      _log.send(e.log_severity, "[#{target_name}] #{e.message}")
      ems.try(:update,
              :last_metrics_error       => :invalid,
              :last_metrics_update_date => Time.now.utc)
      raise
    end

    Benchmark.realtime_block(:collect_data) do
      begin
        context.collect_metrics
      rescue NoMetricsFoundError => e
        _log.warn("Metrics missing: [#{target_name}] #{e.message}")
      rescue StandardError => e
        _log.error("Metrics unavailable: [#{target_name}] #{e.message}")
        ems.update(:last_metrics_error       => :unavailable,
                              :last_metrics_update_date => Time.now.utc) if ems
        raise
      end
    end

    ems.update(:last_metrics_error        => nil,
               :last_metrics_update_date  => Time.now.utc,
               :last_metrics_success_date => Time.now.utc) if ems

    [{target.ems_ref => VIM_STYLE_COUNTERS},
     {target.ems_ref => context.ts_values}]
  end

  private

  def target_name
    @target_name ||= begin
      t = target || ems
      "#{t.class.name.demodulize}(#{t.id})"
    end
  end
end
