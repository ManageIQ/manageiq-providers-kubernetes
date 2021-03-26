describe ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture do
  before do
    # @miq_server is required for worker_settings to work
    @miq_server = EvmSpecHelper.local_miq_server(:is_master => true)
    @hawkular_force_legacy_settings_false = {
      :workers => {
        :worker_base => {
          :queue_worker_base => {
            :ems_metrics_collector_worker => {
              :ems_metrics_collector_worker_kubernetes => {
                :hawkular_force_legacy => false
              }
            }
          }
        }
      }
    }

    @ems_kubernetes = FactoryBot.create(
      :ems_kubernetes,
      :connection_configurations => [{:endpoint       => {:role => :hawkular},
                                      :authentication => {:role => :hawkular}}],
    ).tap { |ems| ems.authentications.each { |auth| auth.update!(:status => "Valid") } }

    @ems_kubernetes_prometheus = FactoryBot.create(
      :ems_kubernetes,
      :connection_configurations => [{:endpoint       => {:role => :prometheus},
                                      :authentication => {:role => :prometheus}}],
    ).tap { |ems| ems.authentications.each { |auth| auth.update!(:status => "Valid") } }

    @node = FactoryBot.create(
      :kubernetes_node,
      :name                  => 'node',
      :ext_management_system => @ems_kubernetes,
      :ems_ref               => 'target'
    )

    @node_prometheus = FactoryBot.create(
      :kubernetes_node,
      :name                  => 'node',
      :ext_management_system => @ems_kubernetes_prometheus,
      :ems_ref               => 'target'
    )

    @node.computer_system.hardware = FactoryBot.create(
      :hardware,
      :cpu_total_cores => 2,
      :memory_mb       => 2048
    )

    @node_prometheus.computer_system.hardware = FactoryBot.create(
      :hardware,
      :cpu_total_cores => 2,
      :memory_mb       => 2048
    )

    @group = FactoryBot.create(
      :container_group,
      :ext_management_system => @ems_kubernetes,
      :container_node        => @node,
      :ems_ref               => 'group'
    )

    @container = FactoryBot.create(
      :kubernetes_container,
      :name                  => 'container',
      :container_group       => @group,
      :ext_management_system => @ems_kubernetes,
      :ems_ref               => 'target'
    )
  end

  context "#perf_capture_object" do
    it "returns the correct class" do
      expect(@ems_kubernetes.perf_capture_object.class).to eq(described_class)
    end
  end

  context "#capture_context" do
    it "detect prometheus metrics provider" do
      metric_capture = described_class.new(@node_prometheus)
      context = metric_capture.capture_context(
        @ems_kubernetes_prometheus,
        @node_prometheus,
        5.minutes.ago,
        0.minutes.ago
      )

      expect(context).to be_a(described_class::PrometheusCaptureContext)
    end

    it "detect hawkular metrics provider without m metric endpoint" do
      stub_settings_merge(@hawkular_force_legacy_settings_false)
      allow_any_instance_of(described_class::HawkularCaptureContext)
        .to receive(:m_endpoint?)
        .and_return(false)

      metric_capture = described_class.new(@node)
      context = metric_capture.capture_context(
        @ems_kubernetes,
        @node,
        5.minutes.ago,
        0.minutes.ago
      )

      expect(context).to be_a(described_class::HawkularLegacyCaptureContext)
    end

    it "detect hawkular metrics provider" do
      stub_settings_merge(@hawkular_force_legacy_settings_false)
      allow_any_instance_of(described_class::HawkularCaptureContext)
        .to receive(:m_endpoint?)
        .and_return(true)

      metric_capture = described_class.new(@node)
      context = metric_capture.capture_context(
        @ems_kubernetes,
        @node,
        5.minutes.ago,
        0.minutes.ago
      )

      expect(context).to be_a(described_class::HawkularCaptureContext)
    end

    it "detect hawkular metrics provider, force legacy collector" do
      allow_any_instance_of(described_class::HawkularCaptureContext)
        .to receive(:m_endpoint?)
        .and_return(true)

      metric_capture = described_class.new(@node)
      context = metric_capture.capture_context(
        @ems_kubernetes,
        @node,
        5.minutes.ago,
        0.minutes.ago
      )

      expect(context).to be_a(described_class::HawkularLegacyCaptureContext)
    end
  end

  context "#perf_collect_metrics" do
    it "fails when no ems is defined" do
      @node.ext_management_system = nil
      expect { @node.perf_collect_metrics('interval_name') }.to raise_error(described_class::TargetValidationError)
    end

    it "fails when no cpu cores are defined" do
      @node.hardware.cpu_total_cores = nil
      expect { @node.perf_collect_metrics('interval_name') }.to raise_error(described_class::TargetValidationError)
    end

    it "fails when memory is not defined" do
      @node.hardware.memory_mb = nil
      expect { @node.perf_collect_metrics('interval_name') }.to raise_error(described_class::TargetValidationError)
    end

    # TODO: include also sort_and_normalize in the tests
    METRICS_EXERCISES = [
      {
        :counters           => [
          {
            :args => 'cpu/usage',
            :data => [
              {'start' => 1_446_500_000_000, 'end' => 1_446_500_060_000, 'min' => 0},
              {'start' => 1_446_500_060_000, 'end' => 1_446_500_120_000, 'min' => 12_000_000_000},
            ]
          },
          {
            :args => 'network/tx',
            :data => [
              {'start' => 1_446_500_000_000, 'end' => 1_446_500_060_000, 'min' => 0},
              {'start' => 1_446_500_060_000, 'end' => 1_446_500_120_000, 'min' => 460_800}
            ]
          },
          {
            :args => 'network/rx',
            :data => [
              {'start' => 1_446_500_000_000, 'end' => 1_446_500_060_000, 'min' => 0},
              {'start' => 1_446_500_060_000, 'end' => 1_446_500_120_000, 'min' => 153_600}
            ]
          }
        ],
        :gauges             => [
          {
            :args => 'memory/working_set',
            :data => [
              {'start' => 1_446_500_000_000, 'end' => 1_446_500_060_000, 'min' => 1_073_741_824}
            ]
          }
        ],
        :node_expected      => {
          Time.at(1_446_500_000).utc => {
            "cpu_usage_rate_average"     => 10.0,
            "mem_usage_absolute_average" => 50.0,
            "net_usage_rate_average"     => 10.0
          }
        },
        :container_expected => {
          Time.at(1_446_500_000).utc => {
            "cpu_usage_rate_average"     => 10.0,
            "mem_usage_absolute_average" => 50.0
          }
        }
      },
      {
        :counters           => [
          {
            :args => 'cpu/usage',
            :data => [
              {'start' => 1_446_499_940_000, 'end' => 1_446_500_000_000, 'min' => 0},
              {'start' => 1_446_500_000_000, 'end' => 1_446_500_060_000, 'min' => 12_000_000_000}
            ]
          },
          {
            :args => 'network/tx',
            :data => [
              {'start' => 1_446_499_940_000, 'end' => 1_446_500_000_000, 'min' => 0},
              {'start' => 1_446_500_000_000, 'end' => 1_446_500_060_000, 'min' => 460_800}
            ]
          },
          {
            :args => 'network/rx',
            :data => [
              {'start' => 1_446_499_940_000, 'end' => 1_446_500_000_000, 'min' => 0},
              {'start' => 1_446_500_000_000, 'end' => 1_446_500_060_000, 'min' => 153_600}
            ]
          }
        ],
        :gauges             => [
          {
            :args => 'memory/working_set',
            :data => [
              {'start' => 1_446_500_000_000, 'end' => 1_446_500_060_000, 'min' => 1_073_741_824}
            ]
          }
        ],
        :node_expected      => {},
        :container_expected => {}
      }
    ]

    it "node counters and gauges are correctly processed" do
      METRICS_EXERCISES.each do |exercise|
        exercise[:counters].each do |metrics|
          allow_any_instance_of(described_class::HawkularLegacyCaptureContext)
            .to receive(:fetch_counters_data)
            .with("machine/node/#{metrics[:args]}")
            .and_return(metrics[:data])
        end

        exercise[:gauges].each do |metrics|
          allow_any_instance_of(described_class::HawkularLegacyCaptureContext)
            .to receive(:fetch_gauges_data)
            .with("machine/node/#{metrics[:args]}")
            .and_return(metrics[:data])
        end

        _, values_by_ts = @node.perf_collect_metrics('realtime')

        expect(values_by_ts['target']).to eq(exercise[:node_expected])
      end
    end

    it "container counters and gauges are correctly processed" do
      METRICS_EXERCISES.each do |exercise|
        exercise[:counters].each do |metrics|
          allow_any_instance_of(described_class::HawkularLegacyCaptureContext)
            .to receive(:fetch_counters_data)
            .with("container/group/#{metrics[:args]}")
            .and_return(metrics[:data])
        end

        exercise[:gauges].each do |metrics|
          allow_any_instance_of(described_class::HawkularLegacyCaptureContext)
            .to receive(:fetch_gauges_data)
            .with("container/group/#{metrics[:args]}")
            .and_return(metrics[:data])
        end

        _, values_by_ts = @container.perf_collect_metrics('realtime')

        expect(values_by_ts['target']).to eq(exercise[:container_expected])
      end
    end
  end
end
