describe ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture do
  let(:ems)               { FactoryBot.create(:ems_kubernetes_with_zone, :with_metrics_endpoint) }
  let(:container_project) { FactoryBot.create(:container_project,          :ext_management_system => ems) }
  let!(:group)            { FactoryBot.create(:kubernetes_container_group, :ext_management_system => ems, :container_node => node) }
  let!(:container)        { FactoryBot.create(:kubernetes_container,       :ext_management_system => ems, :container_group => group, :container_project => container_project) }
  let(:node) do
    FactoryBot.create(:kubernetes_node, :name => 'node', :ext_management_system => ems, :ems_ref => 'target').tap do |node|
      node.computer_system.hardware = FactoryBot.create(:hardware, :cpu_total_cores => 2, :memory_mb => 2_048)
    end
  end

  context "#perf_capture_object" do
    it "returns the correct class" do
      expect(ems.perf_capture_object.class).to eq(described_class)
    end
  end

  context "#build_capture_context!" do
    it "detect prometheus metrics provider" do
      metric_capture = described_class.new(node)
      context        = metric_capture.build_capture_context!(ems, node, 5.minutes.ago, 0.minutes.ago)

      expect(context).to be_a(described_class::PrometheusCaptureContext)
    end
  end

  context "#perf_capture_all_queue" do
    it "returns the objects" do
      expect(ems.perf_capture_object.perf_capture_all_queue).to include("Container" => [container], "ContainerGroup" => [group], "ContainerNode" => [node])
    end

    context "with a missing metrics endpoint" do
      let(:ems) { FactoryBot.create(:ems_kubernetes) }

      it "returns no objects" do
        expect(ems.perf_capture_object.perf_capture_all_queue).to be_empty
      end
    end

    context "with invalid authentication on the metrics endpoint" do
      let(:ems) { FactoryBot.create(:ems_kubernetes_with_zone, :with_metrics_endpoint, :with_invalid_auth) }

      it "returns no objects" do
        expect(ems.perf_capture_object.perf_capture_all_queue).to be_empty
      end
    end
  end

  context "#perf_collect_metrics" do
    it "fails when no ems is defined" do
      node.ext_management_system = nil
      expect { node.perf_collect_metrics('interval_name') }.to raise_error(described_class::TargetValidationError)
    end

    it "fails when no cpu cores are defined" do
      node.hardware.cpu_total_cores = nil
      expect { node.perf_collect_metrics('interval_name') }.to raise_error(described_class::TargetValidationError)
    end

    it "fails when memory is not defined" do
      node.hardware.memory_mb = nil
      expect { node.perf_collect_metrics('interval_name') }.to raise_error(described_class::TargetValidationError)
    end
  end
end
