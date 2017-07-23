describe ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusCaptureContext do
  @node = nil

  before(:each) do
    allow(MiqServer).to receive(:my_zone).and_return("default")
    hostname = 'capture.context.com'
    token = 'theToken'

    @ems = FactoryGirl.create(
      :ems_openshift,
      :name                      => 'OpenShiftProvider',
      :connection_configurations => [{:endpoint       => {:role       => :default,
                                                          :hostname   => hostname,
                                                          :port       => "8443",
                                                          :verify_ssl => false},
                                      :authentication => {:role     => :bearer,
                                                          :auth_key => token,
                                                          :userid   => "_"}},
                                     {:endpoint       => {:role       => :prometheus,
                                                          :hostname   => hostname,
                                                          :port       => "443",
                                                          :verify_ssl => false},
                                      :authentication => {:role     => :prometheus,
                                                          :auth_key => token,
                                                          :userid   => "_"}}]
    )

    if @node.nil?
      VCR.use_cassette("#{described_class.name.underscore}_refresh",
                       :match_requests_on => [:path,]) do # , :record => :new_episodes) do
        EmsRefresh.refresh(@ems)
        @node = @ems.container_nodes.first
        pod = @ems.container_groups.first
        container = @ems.containers.first

        @targets = [['node', @node], ['pod', pod], ['container', container]]
      end
    end
  end

  it "will read prometheus metrics" do
    start_time = Time.parse("2017-07-12 06:40:42 UTC").utc
    end_time   = Time.parse("2017-07-12 09:45:42 UTC").utc
    interval   = 20

    @targets.each do |target_name, target|
      VCR.use_cassette("#{described_class.name.underscore}_#{target_name}_metrics") do # , :record => :new_episodes) do
        context = ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusCaptureContext.new(
          target, start_time, end_time, interval
        )

        data = context.collect_metrics

        expect(data).to be_a_kind_of(Array)
      end
    end
  end

  it "will read only specific timespan prometheus metrics" do
    start_time = Time.parse("2017-07-12 06:40:42 UTC").utc
    end_time   = Time.parse("2017-07-12 06:45:42 UTC").utc
    interval   = 20

    @targets.each do |target_name, target|
      VCR.use_cassette("#{described_class.name.underscore}_#{target_name}_timespan") do # , :record => :new_episodes) do
        context = ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusCaptureContext.new(
          target, start_time, end_time, interval
        )

        data = context.collect_metrics

        expect(data.count).to be < 18
      end
    end
  end
end
