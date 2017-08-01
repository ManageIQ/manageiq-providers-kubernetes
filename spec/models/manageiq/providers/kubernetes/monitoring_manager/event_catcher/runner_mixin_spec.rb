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

  context "#find_target" do
    it "finds a target container node" do
      target = FactoryGirl.create(:container_node)
      labels = {
        "instance" => target.name
      }
      expect(subject.find_target(labels)).to eq(target)
    end

    it "logs error and returns nil if the node does not exist" do
      target = FactoryGirl.build(:container_node)
      labels = {
        "instance" => target.name
      }
      expect($cn_monitoring_log).to receive(:error)
      expect(subject.find_target(labels)).to eq(nil)
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
    let(:event) { { "startsAt" => "2017-07-27T14:23:00.457131488Z" } }
    let(:labels) { { "instance" => "vm-34.173", "container" => "nginx", "alertname" => "alert1"} }
    let(:annotations) { { "url" => "example.com" } }
    it "generates different identifiers for events with different labels" do
      expect(
        subject.incident_identifier(
          event,
          labels,
          annotations,
        )
      ).not_to eq(
        subject.incident_identifier(
          event,
          labels.merge("instance" => "vm-34.174"),
          annotations,
        )
      )
    end

    it "generates different identifiers for events with different start times" do
      expect(
        subject.incident_identifier(
          event.merge("startsAt" => "2017-07-27T14:23:01.457131488Z"),
          labels,
          annotations,
        )
      ).not_to eq(
        subject.incident_identifier(
          event,
          labels,
          annotations,
        )
      )
    end

    it "generates equal identifiers for events equal in labels and start date" do
      expect(
        subject.incident_identifier(
          event,
          labels,
          annotations,
        )
      ).to eq(
        subject.incident_identifier(
          event,
          labels,
          annotations,
        )
      )
    end
  end
end
