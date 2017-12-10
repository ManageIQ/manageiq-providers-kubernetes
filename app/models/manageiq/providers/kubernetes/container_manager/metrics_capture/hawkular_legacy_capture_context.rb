class ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture
  class HawkularLegacyCaptureContext
    include ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::HawkularClientMixin
    include CaptureContextMixin

    def collect_node_metrics
      cpu_resid = "machine/#{@target.name}/cpu/usage"
      process_cpu_counters_rate(fetch_counters_rate(cpu_resid))

      mem_resid = "machine/#{@target.name}/memory/usage"
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

      mem_resid = "#{@target.name}/#{group_id}/memory/usage"
      process_mem_gauges_data(fetch_gauges_data(mem_resid))
    end

    def collect_group_metrics
      group_id = @target.ems_ref

      cpu_counters = @target.containers.collect do |c|
        fetch_counters_rate("#{c.name}/#{group_id}/cpu/usage")
      end
      process_cpu_counters_rate(compute_summation(cpu_counters))

      mem_gauges = @target.containers.collect do |c|
        fetch_gauges_data("#{c.name}/#{group_id}/memory/usage")
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
  end
end
