describe ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture do
  before do
    # @miq_server is required for worker_settings to work
    @miq_server = EvmSpecHelper.local_miq_server(:is_master => true)
    @ems_kubernetes = FactoryBot.create(
      :ems_kubernetes,
      :connection_configurations => [{:endpoint       => {:role => :prometheus},
                                      :authentication => {:role => :prometheus}}],
    ).tap { |ems| ems.authentications.each { |auth| auth.update!(:status => "Valid") } }
    @container_project = FactoryBot.create(:container_project, :ext_management_system => @ems_kubernetes)

    @node = FactoryBot.create(
      :kubernetes_node,
      :name                  => 'node',
      :ext_management_system => @ems_kubernetes,
      :ems_ref               => 'target'
    )

    @node.computer_system.hardware = FactoryBot.create(
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
      :container_project     => @container_project,
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
      metric_capture = described_class.new(@node)
      context = metric_capture.capture_context(
        @ems_kubernetes,
        @node,
        5.minutes.ago,
        0.minutes.ago
      )

      expect(context).to be_a(described_class::PrometheusCaptureContext)
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
  end
end
