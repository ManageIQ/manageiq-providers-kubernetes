class ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture
  class HawkularLegacyCaptureContext
    include ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::HawkularClientMixin
    include CaptureContextMixin

    def collect_node_metrics
      cpu_resid = "machine/#{@target.name}/cpu/usage"
      process_cpu_counters_rate(fetch_counters_rate(cpu_resid))

      mem_resid = "machine/#{@target.name}/memory/working_set"
      process_mem_gauges_data(fetch_gauges_data(mem_resid))

      net_resid = "machine/#{@target.name}/network"
      net_counters = [fetch_counters_rate("#{net_resid}/tx"),
                      fetch_counters_rate("#{net_resid}/rx")]

      process_net_counters_rate(compute_summation(net_counters))
    end

    def collect_container_metrics
      group_id = @target.container_group.ems_ref

      cpu_resid = "#{@target.name}/#{group_id}/cpu/usage"
      process_cpu_counters_rate(fetch_counters_rate(cpu_resid))

      mem_resid = "#{@target.name}/#{group_id}/memory/working_set"
      process_mem_gauges_data(fetch_gauges_data(mem_resid))
    end

    def collect_group_metrics
      group_id = @target.ems_ref

      cpu_counters = @target.containers.collect do |c|
        fetch_counters_rate("#{c.name}/#{group_id}/cpu/usage")
      end
      process_cpu_counters_rate(compute_summation(cpu_counters))

      mem_gauges = @target.containers.collect do |c|
        fetch_gauges_data("#{c.name}/#{group_id}/memory/working_set")
      end
      process_mem_gauges_data(compute_summation(mem_gauges))

      net_resid = "pod/#{group_id}/network"
      net_counters = [fetch_counters_rate("#{net_resid}/tx"),
                      fetch_counters_rate("#{net_resid}/rx")]
      process_net_counters_rate(compute_summation(net_counters))
    end

    def fetch_counters_data(resource)
      sort_and_normalize(
        hawkular_client.counters.get_data(
          resource,
          :starts         => @starts - @interval.in_milliseconds,
          :ends           => @ends,
          :bucketDuration => "#{@interval}s"
        )
      )
    rescue StandardError => e
      raise CollectionFailure, "#{e.class.name}: #{e.message}"
    end

    def fetch_gauges_data(resource)
      sort_and_normalize(
        hawkular_client.gauges.get_data(
          resource,
          :starts         => @starts,
          :ends           => @ends,
          :bucketDuration => "#{@interval}s"
        )
      )
    rescue StandardError => e
      raise CollectionFailure, "#{e.class.name}: #{e.message}"
    end

    def sort_and_normalize(data)
      # Sorting and removing last entry because always incomplete
      # as it's still in progress.
      norm_data = (data.sort_by { |x| x['start'] }).slice(0..-2)
      norm_data.reject { |x| x.values.include?('NaN') || x['empty'] == true }
    end

    private

    CPU_NANOSECONDS = 1e09

    def target_name
      "#{@target.class.name.demodulize}(#{@target.id})"
    end

    def fetch_counters_rate(resource)
      compute_derivative(fetch_counters_data(resource))
    end

    def process_cpu_counters_rate(counters_rate)
      @metrics |= ['cpu_usage_rate_average'] unless counters_rate.empty?
      sec_cpu_time = @node_cores * CPU_NANOSECONDS
      counters_rate.each do |x|
        interval = (x['end'] - x['start']) / 1.in_milliseconds
        timestamp = Time.at(x['start'] / 1.in_milliseconds).utc
        avg_usage = (x['min'] * 100.0) / (sec_cpu_time * interval)
        @ts_values[timestamp]['cpu_usage_rate_average'] = avg_usage
      end
    end

    def process_mem_gauges_data(gauges_data)
      @metrics |= ['mem_usage_absolute_average'] unless gauges_data.empty?
      gauges_data.each do |x|
        timestamp = Time.at(x['start'] / 1.in_milliseconds).utc
        avg_usage = (x['min'] / 1.megabytes) * 100.0 / @node_memory
        @ts_values[timestamp]['mem_usage_absolute_average'] = avg_usage
      end
    end

    def process_net_counters_rate(counters_rate)
      @metrics |= ['net_usage_rate_average'] unless counters_rate.empty?
      counters_rate.each do |x|
        interval = (x['end'] - x['start']) / 1.in_milliseconds
        timestamp = Time.at(x['start'] / 1.in_milliseconds).utc
        avg_usage_kb = x['min'] / (1.kilobyte.to_f * interval)
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
            'min'   => sum['min'] + n['min']
          }
        end
      end
    end

    def compute_derivative(counters)
      counters.each_cons(2).map do |prv, n|
        # Add min, median, min, percentile95th, etc. if needed
        # time window:
        # 00:00                                        01:00
        # ^ (sample start time)                        ^ (next sample start time)
        # ^ (sample min/max/avg value)                 ^ (next sample min/max/avg value)
        #       ^ (real sample time)         ^ (real sample time)          ^ (real sample time)
        #      ^ (real sample value)        ^ (real sample value)           ^ (real sample value)
        # we use:
        # (T = start of window timestamp, V = min value of window samples)
        # because the min value is the value of the sample closest to start of window.
        {
          'start' => prv['start'],
          'end'   => n['start'],
          'min'   => n['min'] - prv['min']
        }
      end
    end
  end
end
