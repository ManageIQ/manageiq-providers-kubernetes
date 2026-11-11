describe ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusCaptureContext do
  before(:each) do
    @record = :none
    # @record = :new_episodes

    master_hostname = 'api.crc.testing'
    hostname = 'prometheus-k8s-openshift-monitoring.apps-crc.testing'
    token = 'BEARER_TOKEN'

    @ems = FactoryBot.create(
      :ems_kubernetes_with_zone,
      :name                      => 'KubernetesProvider',
      :connection_configurations => [{:endpoint       => {:role       => :default,
                                                          :hostname   => master_hostname,
                                                          :port       => "6443",
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

    VCR.use_cassette("#{described_class.name.underscore}_refresh",
                     :match_requests_on => [:path,], :record => @record) do
      EmsRefresh.refresh(@ems)
      @ems.reload

      @node = @ems.container_nodes.last
      pod = @ems.container_groups.last
      container = @ems.containers.last
      @targets = [['node', @node], ['pod', pod], ['container', container]]
    end
  end

  it "will read prometheus metrics" do
    start_time = Time.parse("2020-06-04 20:00:00 UTC").utc
    end_time   = Time.parse("2020-06-04 20:10:00 UTC").utc
    interval   = 60

    @targets.each do |target_name, target|
      VCR.use_cassette("#{described_class.name.underscore}_#{target_name}_metrics", :record => @record) do
        context = ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusCaptureContext.new(
          target, start_time, end_time, interval
        )

        data = context.collect_metrics

        expect(data).to be_a_kind_of(Hash)
        expect(data.keys).to include(start_time, end_time)
        expect(data[start_time].keys).to include(
          "cpu_usage_rate_average",
          "mem_usage_absolute_average"
        )
      end
    end
  end

  it "will read only specific timespan prometheus metrics" do
    start_time = Time.parse("2020-06-04 20:00:00 UTC").utc
    end_time   = Time.parse("2020-06-04 20:10:00 UTC").utc
    interval   = 60

    @targets.each do |target_name, target|
      VCR.use_cassette("#{described_class.name.underscore}_#{target_name}_timespan", :record => @record) do
        context = ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusCaptureContext.new(
          target, start_time, end_time, interval
        )

        data = context.collect_metrics

        expect(data.count).to be > 8
        expect(data.count).to be < 13
      end
    end
  end

  describe "#ts_values" do
    let(:start_time) { Time.parse("2020-06-04 20:00:00 UTC").utc }
    let(:end_time)   { Time.parse("2020-06-04 20:10:00 UTC").utc }
    let(:interval)   { 60 }
    let!(:context) { ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusCaptureContext.new(@node, start_time, end_time, interval) }

    context "with no missing metrics" do
      before do
        ts_values = context.instance_variable_get(:@ts_values)
        ts_values[start_time] = {"cpu_usage_rate_average" => [1], "container_memory_usage_bytes" => [1], "net_usage_rate_average" => [1]}
        ts_values[end_time] = {"cpu_usage_rate_average" => [1], "container_memory_usage_bytes" => [1], "net_usage_rate_average" => [1]}
      end

      it "returns all timestamps" do
        expect(context.ts_values.keys).to include(start_time, end_time)
      end
    end

    context "with some timestamps missing metrics" do
      before do
        ts_values = context.instance_variable_get(:@ts_values)
        ts_values[start_time] = {"cpu_usage_rate_average" => [1], "container_memory_usage_bytes" => [1], "net_usage_rate_average" => [1]}
        ts_values[end_time] = {"cpu_usage_rate_average" => [1], "net_usage_rate_average" => [1]}
      end

      it "only returns timestamps with all metrics" do
        expect(context.ts_values.keys).not_to include(end_time)
      end
    end

    context "with some missing metrics from all timestamps" do
      before do
        ts_values = context.instance_variable_get(:@ts_values)
        ts_values[start_time] = {"cpu_usage_rate_average" => [1], "net_usage_rate_average" => [1]}
        ts_values[end_time] = {"cpu_usage_rate_average" => [1], "net_usage_rate_average" => [1]}
      end

      it "returns all timestamps" do
        expect(context.ts_values.keys).to include(start_time, end_time)
      end
    end
  end
end
