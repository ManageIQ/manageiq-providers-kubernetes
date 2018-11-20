describe ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::HawkularCaptureContext do
  @node = nil

  before(:each) do
    hostname = 'capture.context.com'
    token = 'theToken'

    @ems = FactoryGirl.create(
      :ems_kubernetes_with_zone,
      :name                      => 'KubernetesProvider',
      :connection_configurations => [{:endpoint       => {:role       => :default,
                                                          :hostname   => hostname,
                                                          :port       => "8443",
                                                          :verify_ssl => false},
                                      :authentication => {:role     => :bearer,
                                                          :auth_key => token,
                                                          :userid   => "_"}},
                                     {:endpoint       => {:role       => :hawkular,
                                                          :hostname   => hostname,
                                                          :port       => "443",
                                                          :verify_ssl => false},
                                      :authentication => {:role     => :hawkular,
                                                          :auth_key => token,
                                                          :userid   => "_"}}]
    )

    if @node.nil?
      VCR.use_cassette("#{described_class.name.underscore}_refresh",
                       :match_requests_on => [:path,]) do # , :record => :new_episodes) do
        EmsRefresh.refresh(@ems)
        @ems.reload

        @node = @ems.container_nodes.find_by(:name => "yaacov-3-master001.10.35.48.34.nip.io")
        pod = @ems.container_groups.find_by(:name => "docker-registry-1-jnrtt")
        container = pod.containers.find_by(:name => "registry")

        @targets = [['node', @node], ['pod', pod], ['container', container]]
      end
    end
  end

  it "will read hawkular status" do
    start_time = Time.parse("2018-11-19 18:35:42 UTC").utc
    end_time   = nil
    interval   = nil

    VCR.use_cassette("#{described_class.name.underscore}_status") do # , :record => :new_episodes) do
      context = ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::HawkularCaptureContext.new(
        @node, start_time, end_time, interval
      )

      metrics = {"MetricsService"         => "STARTED",
                 "Implementation-Version" => "0.28.4.Final-redhat-1",
                 "Built-From-Git-SHA1"    => "9ffa8dd648ba0b24bdc52c1717a9b0c0ae1f1472",
                 "Cassandra"              => "up"}

      data = context.hawkular_client.http_get('/status')

      expect(data).to eq(metrics)
    end
  end

  it "will discover m endpoint" do
    start_time = Time.parse("2018-11-19 18:35:42 UTC").utc
    end_time   = nil
    interval   = nil

    VCR.use_cassette("#{described_class.name.underscore}_m_endpoint") do # , :record => :new_episodes) do
      context = ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::HawkularCaptureContext.new(
        @node, start_time, end_time, interval
      )

      expect(context.m_endpoint?).to be_truthy
    end
  end

  it "will read hawkular metrics" do
    start_time = Time.parse("2018-11-19 18:40:42 UTC").utc
    end_time   = nil
    interval   = 60

    @targets.each do |target_name, target|
      VCR.use_cassette("#{described_class.name.underscore}_#{target_name}_metrics") do # , :record => :new_episodes) do
        context = ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::HawkularCaptureContext.new(
          target, start_time, end_time, interval
        )

        context.collect_metrics
        expect(context.ts_values).to be_a_kind_of(Hash)
      end
    end
  end

  it "will read only specific timespan hawkular metrics" do
    start_time = Time.parse("2018-11-19 16:27:42 UTC").utc
    end_time   = Time.parse("2018-11-19 16:37:42 UTC").utc
    interval   = 60

    @targets.each do |target_name, target|
      VCR.use_cassette("#{described_class.name.underscore}_#{target_name}_timespan") do # , :record => :new_episodes) do
        context = ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::HawkularCaptureContext.new(
          target, start_time, end_time, interval
        )

        context.collect_metrics
        expect(context.ts_values.count).to eq(11)
      end
    end
  end
end
