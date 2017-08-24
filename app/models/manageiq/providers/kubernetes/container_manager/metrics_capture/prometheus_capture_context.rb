class ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture
  class PrometheusCaptureContext
    include ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusClientMixin
    include CaptureContextMixin

    def collect_node_metrics
      # TODO: This function should be replaced to use utilization and rate endoints

      # prometheus field is in sec, multiply by 1e9, sec to ns
      # FIXME: we must update this labels to 3.7 labeling scheme and make sure it's uniqe (using type, id, and namespace labeiing)
      cpu_resid = "sum(container_cpu_usage_seconds_total{container_name=\"\",id=\"/\",instance=\"#{@target.name}\",job=\"kubernetes-nodes\"}) * 1e9"
      process_cpu_counters_rate(fetch_counters_rate(cpu_resid))

      # prometheus field is in bytes
      # FIXME: we must update this labels to 3.7 labeling scheme and make sure it's uniqe (using type, id, and namespace labeiing)
      mem_resid = "sum(container_memory_usage_bytes{container_name=\"\",id=\"/\",instance=\"#{@target.name}\",job=\"kubernetes-nodes\"})"
      process_mem_gauges_data(fetch_counters_data(mem_resid))

      # prometheus field is in bytes
      # FIXME: we must update this labels to 3.7 labeling scheme and make sure it's uniqe (using type, id, and namespace labeiing)
      net_resid_rx = "sum(container_network_receive_bytes_total{container_name=\"\",id=\"/\",instance=\"#{@target.name}\",job=\"kubernetes-nodes\",interface=~\"eth.*\"})"
      net_resid_tx = "sum(container_network_transmit_bytes_total{container_name=\"\",id=\"/\",instance=\"#{@target.name}\",job=\"kubernetes-nodes\",interface=~\"eth.*\"})"

      net_counters = [fetch_counters_rate(net_resid_tx),
                      fetch_counters_rate(net_resid_rx)]

      process_net_counters_rate(compute_summation(net_counters))
    end

    def collect_container_metrics
      # TODO: This function should be replaced to use utilization and rate endoints

      # FIXME: we must update this labels to 3.7 labeling scheme and make sure it's uniqe (using type, id, and namespace labeiing)
      cpu_resid = "sum(container_cpu_usage_seconds_total{container_name=\"#{@target.name}\",job=\"kubernetes-nodes\"}) * 1e9"
      process_cpu_counters_rate(fetch_counters_rate(cpu_resid))

      # FIXME: we must update this labels to 3.7 labeling scheme and make sure it's uniqe (using type, id, and namespace labeiing)
      mem_resid = "sum(container_memory_usage_bytes{container_name=\"#{@target.name}\",job=\"kubernetes-nodes\"})"
      process_mem_gauges_data(fetch_counters_data(mem_resid))
    end

    def collect_group_metrics
      # TODO: This function should be replaced to use utilization and rate endoints

      cpu_counters = @target.containers.collect do |c|
        # FIXME: we must update this labels to 3.7 labeling scheme and make sure it's uniqe (using type, id, and namespace labeiing)
        cpu_resid = "sum(container_cpu_usage_seconds_total{container_name=\"#{c.name}\",job=\"kubernetes-nodes\"}) * 1e9"
        fetch_counters_rate(cpu_resid)
      end
      process_cpu_counters_rate(compute_summation(cpu_counters))

      mem_gauges = @target.containers.collect do |c|
        # FIXME: we must update this labels to 3.7 labeling scheme and make sure it's uniqe (using type, id, and namespace labeiing)
        mem_resid = "sum(container_memory_usage_bytes{container_name=\"#{c.name}\",job=\"kubernetes-nodes\"})"
        fetch_counters_data(mem_resid)
      end
      process_mem_gauges_data(compute_summation(mem_gauges))

      # FIXME: we must update this labels to 3.7 labeling scheme and make sure it's uniqe (using type, id, and namespace labeiing)
      net_resid_rx = "sum(container_network_receive_bytes_total{container_name=\"POD\",pod_name=\"#{@target.name}\",job=\"kubernetes-nodes\",interface=~\"eth.*\"})"
      net_resid_tx = "sum(container_network_transmit_bytes_total{container_name=\"POD\",pod_name=\"#{@target.name}\",job=\"kubernetes-nodes\",interface=~\"eth.*\"})"

      net_counters = [fetch_counters_rate(net_resid_tx),
                      fetch_counters_rate(net_resid_rx)]
      process_net_counters_rate(compute_summation(net_counters))
    end

    def fetch_counters_data(resource)
      start_sec = (@starts / 1_000) - @interval
      end_sec = @ends ? (@ends / 1_000).to_i : Time.now.utc.to_i

      sort_and_normalize(
        prometheus_client.get(
          "query_range",
          :query => resource,
          :start => start_sec.to_i,
          :end   => end_sec,
          :step  => "#{@interval}s"
        )
      )
    rescue StandardError => e
      raise CollectionFailure, "#{e.class.name}: #{e.message}"
    end

    def sort_and_normalize(response)
      response = JSON.parse(response.body)

      if response["status"] == "error"
        raise CollectionFailure, "[#{@target} #{@target.name}] " + response["error"]
      end

      unless response["data"] && response["data"]["result"] && response["data"]["result"][0]
        raise CollectionFailure, "[#{@target} #{@target.name}] No data in response"
      end

      response["data"]["result"][0]["values"].map do |x|
        # prometheus gives the time of last reading:
        # devide and multiply to convert time to start of interval window
        start_sec = (x[0] / @interval).to_i * @interval

        {
          "start" => start_sec.to_i.in_milliseconds,
          "avg"   => x[1].to_f
        }
      end
    end
  end
end
