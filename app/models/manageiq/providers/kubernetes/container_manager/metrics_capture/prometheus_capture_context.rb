class ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture
  class PrometheusCaptureContext
    include ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusClientMixin
    include CaptureContextMixin

    def collect_node_metrics
      cpu_resid = "sum(container_cpu_usage_seconds_total{container_name=\"\",id=\"/\",instance=\"#{@target.hostname}\",job=\"kubernetes-nodes\"})"
      process_cpu_counters_rate(fetch_counters_rate(cpu_resid))

      mem_resid = "sum(container_memory_usage_bytes{container_name=\"\",id=\"/\",instance=\"#{@target.hostname}\",job=\"kubernetes-nodes\"})"
      process_mem_gauges_data(fetch_gauges_data(mem_resid))

      net_resid_rx = "sum(container_network_receive_bytes_total{container_name=\"\",id=\"/\",instance=\"#{@target.hostname}\",job=\"kubernetes-nodes\",interface=~\"eth.*\"})"
      net_resid_tx = "sum(container_network_transmit_bytes_total{container_name=\"\",id=\"/\",instance=\"#{@target.hostname}\",job=\"kubernetes-nodes\",interface=~\"eth.*\"})"

      net_counters = [fetch_counters_rate(net_resid_tx),
                      fetch_counters_rate(net_resid_rx)]

      process_net_counters_rate(compute_summation(net_counters))
    end

    def collect_container_metrics
      # FIXME: container_name => @target.name is a uniqe id ?
      cpu_resid = "sum(container_cpu_usage_seconds_total{container_name=\"#{@target.name}\",job=\"kubernetes-nodes\"})"
      process_cpu_counters_rate(fetch_counters_rate(cpu_resid))

      mem_resid = "sum(container_memory_usage_bytes{container_name=\"#{@target.name}\",job=\"kubernetes-nodes\"})"
      process_mem_gauges_data(fetch_gauges_data(mem_resid))
    end

    def collect_group_metrics
      cpu_counters = @target.containers.collect do |c|
        cpu_resid = "sum(container_cpu_usage_seconds_total{container_name=\"#{c.name}\",job=\"kubernetes-nodes\"})"
        fetch_counters_rate(cpu_resid)
      end
      process_cpu_counters_rate(compute_summation(cpu_counters))

      mem_gauges = @target.containers.collect do |c|
        mem_resid = "sum(container_memory_usage_bytes{container_name=\"#{c.name}\",job=\"kubernetes-nodes\"})"
        fetch_gauges_data(mem_resid)
      end
      process_mem_gauges_data(compute_summation(mem_gauges))

      net_resid_rx = "sum(container_network_receive_bytes_total{container_name=\"POD\",id=\"/\",pod_name=\"#{@target.name}\",job=\"kubernetes-nodes\",interface=~\"eth.*\"})"
      net_resid_tx = "sum(container_network_transmit_bytes_total{container_name=\"POD\",id=\"/\",pod_name=\"#{@target.name}\",job=\"kubernetes-nodes\",interface=~\"eth.*\"})"

      net_counters = [fetch_counters_rate(net_resid_tx),
                      fetch_counters_rate(net_resid_rx)]
      process_net_counters_rate(compute_summation(net_counters))
    end

    def fetch_counters_data(resource)
      sort_and_normalize(
        prometheus_client.get(
          "query_range",
          :query => resource,
          :start => (@start_time - @interval).to_i,
          :end   => Time.now.utc.to_i,
          :step  => @interval.to_i
        )
      )
    rescue SystemCallError, SocketError, OpenSSL::SSL::SSLError => e
      raise CollectionFailure, e.message
    end

    def fetch_gauges_data(resource)
      sort_and_normalize(
        prometheus_client.get(
          "query_range",
          :query => resource,
          :start => @start_time.to_i,
          :end   => Time.now.utc.to_i,
          :step  => @interval.to_i
        )
      )
    rescue SystemCallError, SocketError, OpenSSL::SSL::SSLError => e
      raise CollectionFailure, e.message
    end

    def sort_and_normalize(response)
      # Sorting and removing last entry because always incomplete
      # as it's still in progress.
      JSON.parse(response.body)["data"]["result"][0]["values"].map do |x|
        {"start" => x[0].to_i * 1000, "end" => (x[0].to_i + @interval.to_i) * 1000, "avg" => x[1].to_f}
      end
    end
  end
end
