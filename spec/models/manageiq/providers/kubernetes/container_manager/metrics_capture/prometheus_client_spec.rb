describe ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusClient do
  before(:each) do
    allow(MiqServer).to receive(:my_zone).and_return("default")
    hostname = 'prometheus.example.com'
    token = 'good_token'
    @ems = FactoryGirl.create(
      :ems_kubernetes,
      :name                      => 'KubernetesProvider',
      :connection_configurations => [{:endpoint       => {:role       => :default,
                                                          :hostname   => hostname,
                                                          :port       => "8443",
                                                          :verify_ssl => false},
                                      :authentication => {:authtype => :bearer,
                                                          :auth_key => token}},
                                     {:endpoint       => {:role       => :prometheus,
                                                          :hostname   => hostname,
                                                          :port       => "443",
                                                          :verify_ssl => false},
                                      :authentication => {:authtype => :prometheus,
                                                          :auth_key => token}}]
    )
  end

  it "will try to connect to server" do
    VCR.use_cassette("#{described_class.name.underscore}_try_connect") do # , :record => :new_episodes) do
      client = ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusClient.new(@ems)
      data = client.prometheus_try_connect
      expect(data).to eq(true)
    end
  end

  it "will try to connect to server and fail for bad token" do
    VCR.use_cassette("#{described_class.name.underscore}_fail_connect") do # , :record => :new_episodes) do
      @ems.connection_configurations.prometheus.authentication.auth_key = 'wrong_key'
      client = ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusClient.new(@ems)
      expect { client.prometheus_try_connect }.to raise_error(Prometheus::ApiClient::Client::RequestError)
    end
  end
end
