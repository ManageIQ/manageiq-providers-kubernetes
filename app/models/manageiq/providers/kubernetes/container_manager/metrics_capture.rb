module ManageIQ::Providers
  class Kubernetes::ContainerManager::MetricsCapture < BaseManager::MetricsCapture
    class CollectionFailure < RuntimeError; end

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

    require_nested :HawkularLegacyCaptureContext
    require_nested :HawkularCaptureContext
    require_nested :PrometheusCaptureContext

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
      "net_usage_rate_average" => {
        :counter_key           => "net_usage_rate_average",
        :instance              => "",
        :capture_interval      => INTERVAL.to_s,
        :precision             => 1,
        :rollup                => "average",
        :unit_key              => "kilobytespersecond",
        :capture_interval_name => "realtime"
      }
    }

    def capture_context(ems, target, start_time, end_time)
      # make start_time align to minutes
      start_time = start_time.beginning_of_minute

      # check for prometheus endpoint, ems must be set
      if ems.connection_configurations.prometheus.try(:endpoint)
        PrometheusCaptureContext.new(target, start_time, end_time, INTERVAL)

      # check for hawkualr endpoint
      elsif ems.connection_configurations.hawkular.try(:endpoint)
        context = HawkularCaptureContext.new(target, start_time, end_time, INTERVAL)

        # check for old versions of hawkular endpoints (no /m endpoint)
        unless context.m_endpoint?
          context = HawkularLegacyCaptureContext.new(target, start_time, end_time, INTERVAL)
        end

        context
      end
    end

    def perf_collect_metrics(interval_name, start_time = nil, end_time = nil)
      start_time ||= 15.minutes.ago.beginning_of_minute.utc
      ems = target.ext_management_system

      target_name = "#{target.class.name.demodulize}(#{target.id})"
      _log.info("Collecting metrics for #{target_name} [#{interval_name}] " \
                "[#{start_time}] [#{end_time}]")

      begin
        raise TargetValidationError, "no provider for #{target_name}" if ems.nil?
        context = capture_context(ems, target, start_time, end_time)

        raise TargetValidationWarning, "no metrics endpoint found for #{target_name}" if context.nil?
      rescue TargetValidationError, TargetValidationWarning => e
        _log.send(e.log_severity, "[#{target_name}] #{e.message}")
        ems.try(:update_attributes,
                :last_metrics_error       => :invalid,
                :last_metrics_update_date => Time.now.utc)
        raise
      end

      Benchmark.realtime_block(:collect_data) do
        begin
          context.collect_metrics
        rescue => e
          _log.error("Hawkular metrics service unavailable: #{e.message}")
          ems.update_attributes(:last_metrics_error       => :unavailable,
                                :last_metrics_update_date => Time.now.utc) if ems
          raise
        end
      end

      ems.update_attributes(:last_metrics_error        => nil,
                            :last_metrics_update_date  => Time.now.utc,
                            :last_metrics_success_date => Time.now.utc) if ems

      [{target.ems_ref => VIM_STYLE_COUNTERS},
       {target.ems_ref => context.ts_values}]
    end
  end
end
