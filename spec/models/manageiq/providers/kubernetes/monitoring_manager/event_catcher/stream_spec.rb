describe ManageIQ::Providers::Kubernetes::MonitoringManager::EventCatcher::Stream do
  subject do
    described_class.new(monitoring_manager)
  end

  let(:default_endpoint) { FactoryGirl.create(:endpoint, :role => 'default', :hostname => 'host') }
  let(:default_authentication) { FactoryGirl.create(:authentication, :authtype => 'bearer') }
  let(:prometheus_alerts_endpoint) do
    EvmSpecHelper.local_miq_server(:zone => Zone.seed)
    FactoryGirl.create(
      :endpoint,
      :role       => 'prometheus_alerts',
      :hostname   => 'alerts-prometheus.example.com',
      :port       => 443,
      :verify_ssl => false
    )
  end
  let(:prometheus_authentication) do
    FactoryGirl.create(
      :authentication,
      :authtype => 'prometheus_alerts',
      :auth_key => '_',
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

  context "#last_position" do
    context "when event history is empty" do
      it "calculates an initial start position" do
        expect(
          subject.last_position
        ).to eq(
          ['', 0]
        )
      end
    end

    context "when event history is not empty" do
      before do
        [
          FactoryGirl.create(
            :ems_event,
            :timestamp             => "1970-01-01 00:00:00.000000",
            :ext_management_system => container_manager,
            :full_data             => {
              "generationID" => 'ef2c163d-81d1-48ca-997c-6b16d6acc11a',
              "index"        => 0
            }
          ),
          # not real data because this generation also need a 0 index, but good for the test purpose
          FactoryGirl.create(
            :ems_event,
            :timestamp             => "1970-01-02 00:00:00.000000",
            :ext_management_system => container_manager,
            :full_data             => {
              "generationID" => 'db039689-5016-4cc1-a95f-07b1082679e0',
              "index"        => 1
            }
          ),
        ]
      end
      it "calculates a start position based on the last event" do
        expect(subject.last_position).to eq(['db039689-5016-4cc1-a95f-07b1082679e0', 2])
      end
    end
  end
end
