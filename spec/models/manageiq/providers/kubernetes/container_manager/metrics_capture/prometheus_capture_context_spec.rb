describe ManageIQ::Providers::Kubernetes::ContainerManager::MetricsCapture::PrometheusCaptureContext do
  before(:each) do
    @record = :none
    # @record = :new_episodes

    master_hostname = 'api.crc.testing'
    hostname = 'prometheus-k8s-openshift-monitoring.apps-crc.testing'
    token = 'eyJhbGciOiJSUzI1NiIsImtpZCI6IlpLSkFHTlhvb2xWWDYtMFE0aTdoQnVOVGdqWE1MZlAtM3lHcjZNYjQ3eUEifQ.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJtYW5hZ2VtZW50LWluZnJhIiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9zZWNyZXQubmFtZSI6Im1hbmFnZW1lbnQtYWRtaW4tdG9rZW4tY3BkdHYiLCJrdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3NlcnZpY2UtYWNjb3VudC5uYW1lIjoibWFuYWdlbWVudC1hZG1pbiIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50LnVpZCI6ImRmNTEwZWUzLTFkZGQtNDcyZS1iMjk0LTBhNTljODIyNmVhZCIsInN1YiI6InN5c3RlbTpzZXJ2aWNlYWNjb3VudDptYW5hZ2VtZW50LWluZnJhOm1hbmFnZW1lbnQtYWRtaW4ifQ.cqriwRlFx5o_gberghVB2Hu8f6GNkl3vp_uEMDnQLjU5uxtlcofN2CkdR4CoShRafadPZVBGWRTfJkVTLVpiVrSmHrUDlokLjBToi-ycHhuKUJHZLTBQACkogBov_bYzkhpk3Vk5mBQuduq0shuxStSjPfcfwNMMfsKow43tsKWiH7WcnUGQu8XT_Fi6nHI2w70cPxK21i_U5eCXkThYwfYrDCdOAyAT7sITNJ0svuKF3DqpQduK3zEta28m-wTTqcZwRjjIUAUTKJJX-Vc1hLXzp7OB6xXddqVpKVeIFgChip0elcrkzyx3bwZ6yddnsjZEz4vsJqjMM4qxQ6CUaQ'

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
end
