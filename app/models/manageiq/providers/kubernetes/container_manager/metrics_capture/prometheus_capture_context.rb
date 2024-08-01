class ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture
  class PrometheusCaptureContext
    include ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusClientMixin
    include CaptureContextMixin

    # NOTE: when calculating rate of net_usage and cpu_usage counters we use
    #       Prometheus rate function, AVG_OVER is used for range vector size.
    #       value of AVG_OVER is set to 2m allowing for none aligned or missing
    #       scrapes.
    #
    # rate(v range-vector) calculates the per-second average rate of increase
    # of the time series in the range vector. Breaks in monotonicity (such as
    # counter resets due to target restarts) are automatically adjusted for.
    # Also, the calculation extrapolates to the ends of the time range,
    # allowing for missed scrapes or imperfect alignment of scrape cycles with
    # the range's time period.
    AVG_OVER = "2m".freeze

    def collect_node_metrics
      # set node labels
      labels = labels_to_s(:id => "/", :node => @target.name)
      ne_labels = labels_to_s_ne(
        :node => "",
      )

      @metrics = %w(cpu_usage_rate_average mem_usage_absolute_average net_usage_rate_average)
      collect_metrics_for_labels(labels,ne_labels)
    end

    def collect_container_metrics
      # set container labels
      labels = labels_to_s(
        :container => @target.name,
        :pod       => @target.container_group.name,
        :namespace => @target.container_project.name,
      )
      #set container labels with not equal to condition
      ne_labels = labels_to_s_ne(
        :container => "",
        :container => "POD",
      )

      @metrics = %w(cpu_usage_rate_average mem_usage_absolute_average)
      collect_metrics_for_labels(labels,ne_labels)
    end

    def collect_group_metrics
      # set pod labels
      # NOTE: pod_name="X" willl yield metrics for all the containers
      #       belonging to pod "X" as well as the internal POD container
      #       (OpenShift's equivalent of kubernetes 'pause' pod)

      labels = labels_to_s(
        :pod       => @target.name,
        :namespace => @target.container_project.name,
      )
      ne_labels = labels_to_s_ne(
        :container => "",
        :container => "POD",
      )

      @metrics = %w(cpu_usage_rate_average mem_usage_absolute_average net_usage_rate_average)
      collect_metrics_for_labels(labels,ne_labels)
    end

    def collect_metrics_for_labels(labels,ne_labels)
      # prometheus field is in core usage per sec
      # miq field is in pct of node cpu
      #
      #   rate is the "usage per sec" readings avg over last 5m
      cpu_resid = "sum(rate(container_cpu_usage_seconds_total{#{ne_labels},#{labels}}[#{AVG_OVER}]))"
      fetch_counters_data(cpu_resid, 'cpu_usage_rate_average', @node_cores / 100.0)

      # prometheus field is in bytes, @node_memory is in mb
      # miq field is in pct of node memory
      mem_resid = "sum(container_memory_usage_bytes{#{labels}})"
      fetch_counters_data(mem_resid, 'mem_usage_absolute_average', @node_memory * 1e6 / 100.0)

      # prometheus field is in bytes
      # miq field is on kb ( / 1000 )
      if @metrics.include?('net_usage_rate_average')
        interfaces = "eth.*|ens.*|enp.*|eno.*|enc.*"
        net_resid = "sum(rate(container_network_receive_bytes_total{#{labels},interface=~\"#{interfaces}\"}[#{AVG_OVER}])) + " \
                    "sum(rate(container_network_transmit_bytes_total{#{labels},interface=~\"#{interfaces}\"}[#{AVG_OVER}]))"
        fetch_counters_data(net_resid, 'net_usage_rate_average', 1000.0)
      end

      @ts_values
    end

    def fetch_counters_data(resource, metric_title, conversion_factor = 1)
      start_sec = (@starts / 1_000) - @interval
      end_sec = @ends ? (@ends / 1_000).to_i : Time.now.utc.to_i

      sort_and_normalize(
        prometheus_client.query_range(
          :query => resource,
          :start => start_sec.to_i,
          :end   => end_sec,
          :step  => "#{@interval}s"
        ),
        metric_title,
        conversion_factor
      )
    rescue NoMetricsFoundError
      raise
    rescue StandardError => e
      raise CollectionFailure, "#{e.class.name}: #{e.message}"
    end

    def sort_and_normalize(response, metric_title, conversion_factor)
      unless response["result"] && response["result"][0]
        raise NoMetricsFoundError, "[#{@target} #{@target.name}] No data in response"
      end

      response["result"][0]["values"].map do |x|
        # prometheus gives the time of last reading:
        # devide and multiply to convert time to start of interval window
        start_sec = (x[0] / @interval).to_i * @interval
        timekey = Time.at(start_sec).utc
        value = x[1].to_f / conversion_factor.to_f

        @ts_values[timekey][metric_title] = value
      end
    end
  end
end
