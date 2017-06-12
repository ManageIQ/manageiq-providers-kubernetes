class ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture
  module CaptureContextMixin
    def initialize(target, start_time, end_time, interval)
      @target = target
      @start_time = start_time || 15.minutes.ago.beginning_of_minute.utc
      @end_time = end_time
      @interval = interval
      @tenant = target.try(:container_project).try(:name) || '_system'
      @ext_management_system = @target.ext_management_system || @target.try(:old_ext_management_system)
      @ts_values = Hash.new { |h, k| h[k] = {} }
      @metrics = []

      @node_hardware = if @target.respond_to?(:hardware)
                         @target.hardware
                       else
                         @target.try(:container_node).try(:hardware)
                       end

      @node_cores = @node_hardware.try(:cpu_total_cores)
      @node_memory = @node_hardware.try(:memory_mb)

      validate_target
    end

    def collect_metrics
      case @target
      when ContainerNode  then collect_node_metrics
      when Container      then collect_container_metrics
      when ContainerGroup then collect_group_metrics
      else raise TargetValidationError, "unknown target"
      end
    end

    def ts_values
      # Filtering out entries that are not containing all the metrics.
      # This generally happens because metrics are collected at slightly
      # different times and could produce entries that are incomplete.
      @ts_values.select { |_, v| @metrics.all? { |k| v.key?(k) } }
    end

    private

    CPU_NANOSECONDS = 1e09

    def target_name
      "#{@target.class.name.demodulize}(#{@target.id})"
    end

    def validate_target
      raise TargetValidationError,   "ems not defined"    unless @ext_management_system
      raise TargetValidationWarning, "no associated node" unless @node_hardware

      raise TargetValidationError, "cores not defined"  unless @node_cores.to_i > 0
      raise TargetValidationError, "memory not defined" unless @node_memory.to_i > 0
    end

    def fetch_counters_rate(resource)
      compute_derivative(fetch_counters_data(resource))
    end

    def process_cpu_counters_rate(counters_rate)
      @metrics |= ['cpu_usage_rate_average'] unless counters_rate.empty?
      total_cpu_time = @node_cores * CPU_NANOSECONDS * @interval
      counters_rate.each do |x|
        timestamp = Time.at(x['start'] / 1.in_milliseconds).utc
        avg_usage = (x['avg'] * 100.0) / total_cpu_time
        @ts_values[timestamp]['cpu_usage_rate_average'] = avg_usage
      end
    end

    def process_mem_gauges_data(gauges_data)
      @metrics |= ['mem_usage_absolute_average'] unless gauges_data.empty?
      gauges_data.each do |x|
        timestamp = Time.at(x['start'] / 1.in_milliseconds).utc
        avg_usage = (x['avg'] / 1.megabytes) * 100.0 / @node_memory
        @ts_values[timestamp]['mem_usage_absolute_average'] = avg_usage
      end
    end

    def process_net_counters_rate(counters_rate)
      @metrics |= ['net_usage_rate_average'] unless counters_rate.empty?
      counters_rate.each do |x|
        timestamp = Time.at(x['start'] / 1.in_milliseconds).utc
        avg_usage_kb = x['avg'] / (1.kilobyte.to_f * @interval)
        @ts_values[timestamp]['net_usage_rate_average'] = avg_usage_kb
      end
    end

    def compute_summation(data)
      ts_data = Hash.new { |h, k| h[k] = [] }

      data.flatten.each { |x| ts_data[x['start']] << x }
      ts_data.delete_if { |_k, v| v.length != data.length }

      ts_data.keys.sort.map do |k|
        ts_data[k].inject do |sum, n|
          # Add min, median, max, percentile95th, etc. if needed
          {
            'start' => k,
            'end'   => [sum['end'], n['end']].max,
            'avg'   => sum['avg'] + n['avg']
          }
        end
      end
    end

    def compute_derivative(counters)
      counters.each_cons(2).map do |prv, n|
        # Add min, median, max, percentile95th, etc. if needed
        {
          'start' => n['start'],
          'end'   => n['end'],
          'avg'   => n['avg'] - prv['avg']
        }
      end
    end
  end
end
