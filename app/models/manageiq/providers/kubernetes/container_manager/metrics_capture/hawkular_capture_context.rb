class ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture
  class HawkularCaptureContext
    include ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::HawkularClientMixin
    include CaptureContextMixin

    # if true use node capacity from inventory, o/w query realtime Hawkular capacity
    USE_INVENTORY = true

    METRICS_ENDPOINT = 'm/stats/query'.freeze
    METRICS_NODE_TAGS = 'descriptor_name:' \
      'network/tx_rate|network/rx_rate|' \
      'cpu/usage_rate|memory/usage'.freeze
    METRICS_NODE_KEYS = [
      'cpu/usage_rate',
      'memory/usage',
      'network/rx_rate',
      'network/tx_rate',
    ].freeze
    METRICS_POD_TAGS = 'descriptor_name:' \
      'network/tx_rate|network/rx_rate|' \
      'cpu/usage_rate|memory/usage'.freeze
    METRICS_POD_KEYS = [
      'cpu/usage_rate',
      'memory/usage',
      'network/rx_rate',
      'network/tx_rate',
    ].freeze
    METRICS_CONTAINER_TAGS = 'descriptor_name:' \
      'cpu/usage_rate|memory/usage'.freeze
    METRICS_CONTAINER_KEYS = [
      'cpu/usage_rate',
      'memory/usage',
    ].freeze
    METRICS_CAPACITY_TAGS = 'descriptor_name:cpu/node_capacity|memory/node_capacity'.freeze
    METRICS_CAPACITY_KEYS = [
      'cpu/node_capacity',
      'memory/node_capacity',
    ].freeze
    METRICS_FIELDS = {
      'node'          => {
        'tags' => METRICS_NODE_TAGS,
        'keys' => METRICS_NODE_KEYS,
      },
      'pod'           => {
        'tags' => METRICS_POD_TAGS,
        'keys' => METRICS_POD_KEYS,
      },
      'pod_container' => {
        'tags' => METRICS_CONTAINER_TAGS,
        'keys' => METRICS_CONTAINER_KEYS,
      },
    }.freeze

    def collect_node_metrics
      @metrics = %w(mem_usage_absolute_average cpu_usage_rate_average net_usage_rate_average)

      # query node capacity from Hawkular server
      cpu_node_capacity, mem_node_capacity = collect_node_capacity_metrics(@target.name)

      # query metrics from Hawkular server
      collect_metrics_for_object('node', @target.name)

      # calculate raw metrics into ManageIQ metrics
      calculate_fields(cpu_node_capacity, mem_node_capacity)
    end

    def collect_container_metrics
      @metrics = %w(cpu_usage_rate_average mem_usage_absolute_average)
      host_id = @target.container_node.name
      pod_id = @target.container_group.ems_ref

      # query node capacity from Hawkular server
      cpu_node_capacity, mem_node_capacity = collect_node_capacity_metrics(host_id)

      # query metrics from Hawkular server
      collect_metrics_for_object('pod_container', host_id, pod_id, @target.name)

      # calculate raw metrics into ManageIQ metrics
      calculate_fields(cpu_node_capacity, mem_node_capacity)
    end

    def collect_group_metrics
      @metrics = %w(cpu_usage_rate_average mem_usage_absolute_average net_usage_rate_average)
      host_id = @target.container_node.name

      # query node capacity from Hawkular server
      cpu_node_capacity, mem_node_capacity = collect_node_capacity_metrics(host_id)

      # query metrics from Hawkular server
      collect_metrics_for_object('pod', host_id, @target.ems_ref)

      # calculate raw metrics into ManageIQ metrics
      calculate_fields(cpu_node_capacity, mem_node_capacity)
    end

    # Query the Hawkular server for endpoint "/m" available on new versions
    #
    # @return [Bool] true if context has '/m' endpoint, o/w false
    def m_endpoint?
      hawkular_client.http_get('m?tags=type:none').kind_of?(Hash)
    rescue StandardError
      false
    end

    private

    # Create an initial hash for quering Hawkular metrics.
    #
    # @return [Hash] the hash with start, end and bucketDuration.
    def default_query_hash
      {
        :start          => @starts - @interval.in_milliseconds,
        :end            => @ends,
        :bucketDuration => "#{@interval}s",
      }
    end

    # Create an initial hash for quering Hawkular node capacity.
    #
    # @return [Hash] the hash with start, end and buckets.
    def capacity_query_hash
      {
        :start   => @ends - 5.minutes.in_milliseconds,
        :end     => @ends,
        :buckets => 1,
      }
    end

    # Search for a full key name in the metrics hash.
    #
    # @param type [String] metrics type (e.g. gauge / counter).
    # @param key [String] the metrics key/group_id (e.g. cpu/usage).
    # @return [String] the metrics full key name (e.g. machine/example.com/cpu/usage).
    def get_metrics_key(raw_metrics, type, key)
      raise NoMetricsFoundError, "no #{type} metrics found for [#{@target.name}]" unless raw_metrics[type]

      # each object has only one metrics with some key/group_id ( e.g. each node has only one cpu/usage )
      raw_metrics[type].keys.find { |e| e.ends_with?(key) }
    end

    # Calculate ManageIQ network, cpu and mem metrics for one timestamp value set.
    #
    # Add the network, cpu and mem calculated fields to the @ts_values global struct
    # ( ts_value is a pointer to one element in @ts_values )
    # @param ts_value [data] the metrics timestamp value set
    def calculate_one_timestamp_fields(ts_value, cpu_node_capacity, mem_node_capacity)
      # usage_rate is in milicores/sec, node_capacity is in milicores, we want the value in %/sec
      # multiply by 100 to get percents
      if ts_value['cpu/usage_rate'] && ts_value['memory/usage']
        ts_value['cpu_usage_rate_average'] = ts_value['cpu/usage_rate'] / cpu_node_capacity
        ts_value['mem_usage_absolute_average'] = ts_value['memory/usage'] / mem_node_capacity
      end

      # network/rx_rate is in bytes/sec we want the value in kbyte / sec,
      # devide by 1000
      if ts_value['network/rx_rate'] && ts_value['network/tx_rate']
        ts_value['net_usage_rate_average'] = (ts_value['network/rx_rate'] + ts_value['network/tx_rate']) / 1000.0
      end
    end

    # Calculate ManageIQ metrics.
    #
    # Add the calculated fields to the @ts_values global struct
    def calculate_fields(cpu_node_capacity, mem_node_capacity)
      if cpu_node_capacity.nil? || cpu_node_capacity.zero? || mem_node_capacity.nil? || mem_node_capacity.zero?
        raise CollectionFailure, "node capacity is zero"
      end

      # calculate raw metrics into ManageIQ metrics:
      @ts_values.each do |_, ts_value|
        calculate_one_timestamp_fields(ts_value, cpu_node_capacity / 100.0, mem_node_capacity / 100.0)
      end
    end

    # Query the Hawkular server for metrics.
    #
    # @param tags [String] a Hawkular query tag string (e.g. group_id:/cpu/node_capacity|/memory/node_capacity)
    # @return [Hash] the metrics object returned from the Hawkulat server.
    def query_metrics_by_tags(tags = nil, tenant = nil)
      query_hash = default_query_hash
      query_hash[:tags] = tags

      # query all metrics from Hawkular TSDB
      begin
        hawkular_client(tenant).http_post(METRICS_ENDPOINT, query_hash)
      rescue StandardError => e
        raise CollectionFailure, "#{e.class.name}: #{e.message}"
      end
    end

    # Insert raw values from ManageIQ into the ts_values global variable
    # For one key, full_key pair
    #
    # @param key [String] the metric key ( e.g. 'cpu_usage' ).
    # @param full_key [String] the metric full_key ( e.g. 'machine/<utl>/cpu/usage_rate' ).
    def insert_metrics_key(raw_metrics, key, full_key)
      # insert the raw metrics into the @ts_values global object
      raw_metrics['gauge'][full_key].each do |metric|
        timestamp = Time.at(metric['start'] / 1.in_milliseconds).utc
        @ts_values[timestamp][key] = metric['max'] unless metric['empty']
      end
    end

    # Insert raw values from ManageIQ into the ts_values global variable
    #
    # @param type [String] type in the Hawkular DB.
    def insert_metrics(raw_metrics, type)
      keys = METRICS_FIELDS[type]['keys']

      # pull the raw values from query responce
      keys.each do |key|
        # get the metrics full key e.g.
        #    "cpu/usage_rate" => "machine/<utl>/cpu/usage_rate"
        full_key = get_metrics_key(raw_metrics, 'gauge', key)
        unless full_key
          raise NoMetricsFoundError, "#{key} missing while query metrics"
        end

        # insert the raw metrics into the @ts_values global object
        insert_metrics_key(raw_metrics, key, full_key)
      end
    end

    # Query the Hawkular server for metrics
    #
    # Query metrics and push them into the @ts_values global variable.
    #
    # @param type [String] type in the Hawkular DB.
    # @param host_id [String] host_id/url the identify a node in the Hawkular DB.
    # @param pod_id [String] pod_id of a pod in the Hawkular DB.
    # @param container_name [String] container_name of a container in the Hawkular DB.
    def collect_metrics_for_object(type, host_id = nil, pod_id = nil, container_name = nil)
      tags = METRICS_FIELDS[type]['tags']

      # query metrics
      metric_tags = if type == 'node'
                      "#{tags},type:#{type},host_id:#{host_id}"
                    elsif type == 'pod'
                      "#{tags},type:#{type},host_id:#{host_id},pod_id:#{pod_id}"
                    elsif type == 'pod_container'
                      "#{tags},type:#{type},host_id:#{host_id},pod_id:#{pod_id},container_name:#{container_name}"
                    end
      raw_metrics = query_metrics_by_tags(metric_tags)

      # insert metrics to @ts_values
      insert_metrics(raw_metrics, type)
    end

    # Query the Hawkular server for node capacity metrics
    #
    # @param host_id [String] host_id the identify a node in the Hawkular DB.
    # @return [Array<Float>] node cpu capacity and node memory capacity
    def collect_node_capacity_metrics(host_id)
      if USE_INVENTORY
        # core (1e3 millicore), mb (1e6 byte)
        [@node_cores * 1e3, @node_memory * 1e6]
      else
        # query capacity metrics from Hawkular server
        metric_tags = "#{METRICS_CAPACITY_TAGS},type:node,host_id:#{host_id}"
        query_hash = capacity_query_hash
        query_hash[:tags] = metric_tags

        cpu_full_key = "machine/#{host_id}/cpu/node_capacity"
        mem_full_key = "machine/#{host_id}/memory/node_capacity"

        # query all metrics from Hawkular TSDB
        begin
          capacity_values = hawkular_client("_system").http_post(METRICS_ENDPOINT, query_hash)["gauge"]
        rescue StandardError => e
          raise CollectionFailure, "#{e.class.name}: #{e.message}"
        end

        # set node capacity
        cpu_node_capacity = capacity_values[cpu_full_key][0]["avg"]
        mem_node_capacity = capacity_values[mem_full_key][0]["avg"]

        [cpu_node_capacity, mem_node_capacity]
      end
    end
  end
end
