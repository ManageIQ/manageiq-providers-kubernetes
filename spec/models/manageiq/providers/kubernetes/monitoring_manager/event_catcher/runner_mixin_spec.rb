describe ManageIQ::Providers::Kubernetes::MonitoringManager::EventCatcher::RunnerMixin do
  subject do
    test_class.new(monitoring_manager)
  end

  let(:test_class) do
    Class.new do
      def initialize(ems)
        @ems = ems
      end
    end.include(described_class)
  end

  let(:default_endpoint) { FactoryGirl.create(:endpoint, :role => "default", :hostname => "host") }
  let(:default_authentication) { FactoryGirl.create(:authentication, :authtype => "bearer") }
  let(:prometheus_alerts_endpoint) do
    EvmSpecHelper.local_miq_server(:zone => Zone.seed)
    FactoryGirl.create(
      :endpoint,
      :role       => "prometheus_alerts",
      :hostname   => "alerts-prometheus.example.com",
      :port       => 443,
      :verify_ssl => false
    )
  end
  let(:prometheus_authentication) do
    FactoryGirl.create(
      :authentication,
      :authtype => "prometheus_alerts",
      :auth_key => "_",
    )
  end

  let(:container_manager) do
    FactoryGirl.create(
      :ems_kubernetes,
      :endpoints       => [
        default_endpoint,
        prometheus_alerts_endpoint,
      ],
      :authentications => [
        default_authentication,
        prometheus_authentication,
      ],
    )
  end

  let(:monitoring_manager) { container_manager.monitoring_manager }
  let(:node_annotations) { {"miqTarget" => 'ContainerNode'} }
  let(:ext_annotations) { {"miqTarget" => 'ExtManagementSystem'} }

  context "#find_target" do
    it "binds to container node by default" do
      target = FactoryGirl.create(:container_node, :name => 'testing')
      labels = {
        "instance" => target.name
      }
      expect(subject.find_target({}, labels)).to eq(
        :container_node_name => target.name,
        :container_node_id   => target.id,
        :target_type         => "ContainerNode",
        :target_id           => target.id,
      )
    end

    it "binds to container node if requested explicitly" do
      target = FactoryGirl.create(:container_node, :name => 'testing')
      labels = {
        "instance" => target.name
      }
      expect(subject.find_target(node_annotations, labels)).to eq(
        :container_node_name => target.name,
        :container_node_id   => target.id,
        :target_type         => "ContainerNode",
        :target_id           => target.id,
      )
    end

    it "binds to the ems if requested explicitly" do
      target = FactoryGirl.create(:container_node, :name => 'testing')
      subject.instance_variable_set(:@target_ems_id, 8)
      labels = {
        "instance" => target.name
      }
      expect(subject.find_target(node_annotations, labels).compact).to eq(
        :target_type => "ExtManagementSystem",
        :target_id   => 8,
      )
    end

    it "logs warn and fallsback to the ems if the node does not exist" do
      subject.instance_variable_set(:@target_ems_id, 8)
      labels = { "instance" => "testing" }
      expect($cn_monitoring_log).to receive(:warn)
      expect(subject.find_target(node_annotations, labels).compact).to eq(
        :target_type => "ExtManagementSystem",
        :target_id   => 8,
      )
    end

    it "logs warn and fallsback to the ems if there is no instance annotation" do
      subject.instance_variable_set(:@target_ems_id, 8)
      expect($cn_monitoring_log).to receive(:warn)
      expect(subject.find_target(node_annotations, {}).compact).to eq(
        :target_type => "ExtManagementSystem",
        :target_id   => 8,
      )
    end
  end

  context "#parse_severity" do
    it "parses all known severities" do
      expect(subject.parse_severity("error")).to eq("error")
      expect(subject.parse_severity("warning")).to eq("warning")
      expect(subject.parse_severity("info")).to eq("info")
    end

    it "ignores case" do
      expect(subject.parse_severity("ERROR")).to eq("error")
      expect(subject.parse_severity("WARNING")).to eq("warning")
      expect(subject.parse_severity("INFO")).to eq("info")
    end

    it "defaults to error for unknowns" do
      expect(subject.parse_severity("unknown")).to eq("error")
      expect(subject.parse_severity("")).to eq("error")
      expect(subject.parse_severity(nil)).to eq("error")
    end
  end

  context "#incident_identifier" do
    let(:startsAt) { "2017-07-27T14:23:00.457131488Z" }
    let(:labels) { { "instance" => "vm-34.173", "container" => "nginx", "alertname" => "alert1"} }
    let(:annotations) { { "url" => "example.com" } }
    it "generates different identifiers for events with different labels" do
      expect(
        subject.incident_identifier(
          labels,
          annotations,
          startsAt
        )
      ).not_to eq(
        subject.incident_identifier(
          labels.merge("instance" => "vm-34.174"),
          annotations,
          startsAt
        )
      )
    end

    it "generates different identifiers for events with different start times" do
      expect(
        subject.incident_identifier(
          labels,
          annotations,
          "2017-07-27T00:00:00.457131488Z"
        )
      ).not_to eq(
        subject.incident_identifier(
          labels,
          annotations,
          "2017-07-27T14:23:00.457131488Z"
        )
      )
    end

    it "generates equal identifiers for events equal in labels and annotations" do
      expect(
        subject.incident_identifier(
          labels,
          annotations,
          startsAt
        )
      ).to eq(
        subject.incident_identifier(
          labels,
          annotations,
          startsAt
        )
      )
    end
  end
end
