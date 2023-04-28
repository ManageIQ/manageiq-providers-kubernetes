class ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture
  module CaptureContextMixin
    def initialize(target, start_time, end_time, interval)
      @target = target
      @starts = start_time.to_i.in_milliseconds
      @ends = end_time.to_i.in_milliseconds if end_time
      @interval = interval.to_i
      @tenant = target.try(:container_project).try(:name) || '_system'
      @ext_management_system = @target.ext_management_system
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
      #
      # However, if a requested metric is missing from all timestamps
      #  don't exclude all other values.
      collected_metrics = @ts_values.values.flat_map(&:keys).uniq
      @ts_values.select { |_, v| collected_metrics.all? { |k| v.key?(k) } }
    end

    def validate_target
      raise TargetValidationError,   "ems not defined"    unless @ext_management_system
      raise TargetValidationWarning, "no associated node" unless @node_hardware

      raise TargetValidationError, "cores not defined"  unless @node_cores.to_i > 0
      raise TargetValidationError, "memory not defined" unless @node_memory.to_i > 0
    end
  end
end
