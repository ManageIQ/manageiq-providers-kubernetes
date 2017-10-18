# instantiated at the end
shared_examples "openshift refresher VCR targeted refresh tests" do
  before(:each) do
    allow(MiqServer).to receive(:my_zone).and_return("default")
    hostname          = 'host.example.com'
    token             = 'theToken'
    hawkular_hostname = 'host.example.com'
    
    @ems = FactoryGirl.create(
      :ems_kubernetes,
      :name                      => 'KubernetesProvider',
      :connection_configurations => [{:endpoint       => {:role       => :default,
                                                          :hostname   => hostname,
                                                          :port       => "8443",
                                                          :verify_ssl => false},
                                      :authentication => {:role     => :bearer,
                                                          :auth_key => token,
                                                          :userid   => "_"}},
                                     {:endpoint       => {:role       => :hawkular,
                                                          :hostname   => hawkular_hostname,
                                                          :port       => "443",
                                                          :verify_ssl => false},
                                      :authentication => {:role     => :hawkular,
                                                          :auth_key => token,
                                                          :userid   => "_"}}]
    )
  end

  it ".ems_type" do
    expect(described_class.ems_type).to eq(:kubernetes)
  end

  it "will perform a full refresh on openshift loading only referenced Nodes and Namespaces" do
    stub_settings_merge(
      :ems_refresh => {:kubernetes => {:api_filter_vs_full_list_threshold => 50}}
    )

    full_refresh_test(:targeted_refresh_referenced_nodes_and_namespaces)
  end

  it "will perform a full refresh on openshift loading all Nodes and Namespaces" do
    stub_settings_merge(
      :ems_refresh => {:kubernetes => {:api_filter_vs_full_list_threshold => 0}}
    )

    full_refresh_test(:targeted_refresh_all_nodes_and_namespaces)
  end

  def queue_target!(watch_data_path)
    notice = JSON.parse(File.read(File.join(File.dirname(__FILE__), watch_data_path)))

    # Below, a code from ManageIQ::Providers::Kubernetes::ContainerManager::InventoryCollectorWorker::Runner#do_work
    ems_ref = parse_notice_pod_ems_ref(notice['object'])

    target = ManagerRefresh::Target.new(
      :manager     => @ems,
      :association => :container_groups,
      :manager_ref => ems_ref,
      :options     => {
        :payload => notice['object'],
      }.to_json,
    )

    EmsRefresh.queue_refresh(target)
  end

  def parse_notice_pod_ems_ref(pod)
    pod['metadata']['uid']
  end

  def normal_refresh(suffix)
    queue_target!('watch_pod_stress_4.json')
    queue_target!('watch_pod_stress_5.json')

    VCR.use_cassette(described_class.name.underscore + "_#{suffix}",
                     :match_requests_on => [:path,]) do # , :record => :new_episodes) do

      # There should be 1 refresh Job with 2 targets inside
      expect(MiqQueue.where(:method_name => 'refresh').count).to eq 1
      refresh_job = MiqQueue.where(:method_name => 'refresh').first
      refresh_job.deliver
    end
  end

  def full_refresh_test(suffix)
    2.times do
      @ems.reload
      normal_refresh(suffix)
      @ems.reload

      assert_ems
      assert_table_counts(send("expected_table_counts_#{suffix}"))
      assert_specific_container
      assert_specific_container_group
      assert_specific_container_node
      assert_specific_container_services
      assert_specific_container_image_registry
      assert_specific_container_project
      assert_specific_container_route
      assert_specific_container_build
      assert_specific_container_build_pod
      assert_specific_container_template
      assert_specific_used_container_image(:metadata => true)
    end
  end

  def expected_table_counts_targeted_refresh_all_nodes_and_namespaces
    {
      :computer_system               => 9,
      :container                     => 2,
      :container_build               => 0,
      :container_build_pod           => 0,
      :container_condition           => 42,
      :container_env_var             => 0,
      :container_group               => 2,
      :container_image               => 1,
      :container_image_registry      => 1,
      :container_limit               => 0,
      :container_limit_item          => 0,
      :container_node                => 9,
      :container_port_config         => 0,
      :container_project             => 14,
      :container_quota               => 0,
      :container_quota_item          => 0,
      :container_replicator          => 0,
      :container_route               => 0,
      :container_service             => 0,
      :container_service_port_config => 0,
      :container_template            => 0,
      :container_template_parameter  => 0,
      :container_volume              => 2,
      :custom_attribute              => 58,
      :ext_management_system         => 1,
      :hardware                      => 9,
      :operating_system              => 9,
      :persistent_volume_claim       => 0,
      :security_context              => 2
    }
  end

  def expected_table_counts_targeted_refresh_referenced_nodes_and_namespaces
    {
      :computer_system               => 1,
      :container                     => 2,
      :container_build               => 0,
      :container_build_pod           => 0,
      :container_condition           => 10,
      :container_env_var             => 0,
      :container_group               => 2,
      :container_image               => 1,
      :container_image_registry      => 1,
      :container_limit               => 0,
      :container_limit_item          => 0,
      :container_node                => 1,
      :container_port_config         => 0,
      :container_project             => 1,
      :container_quota               => 0,
      :container_quota_item          => 0,
      :container_replicator          => 0,
      :container_route               => 0,
      :container_service             => 0,
      :container_service_port_config => 0,
      :container_template            => 0,
      :container_template_parameter  => 0,
      :container_volume              => 2,
      :custom_attribute              => 12,
      :ext_management_system         => 1,
      :hardware                      => 1,
      :operating_system              => 1,
      :persistent_volume_claim       => 0,
      :security_context              => 2
    }
  end

  def assert_table_counts(counts)
    actual = {
      :computer_system               => ComputerSystem.count,
      :container                     => Container.count,
      :container_build               => ContainerBuild.count,
      :container_build_pod           => ContainerBuildPod.count,
      :container_condition           => ContainerCondition.count,
      :container_env_var             => ContainerEnvVar.count,
      :container_group               => ContainerGroup.count,
      :container_image               => ContainerImage.count,
      :container_image_registry      => ContainerImageRegistry.count,
      :container_limit               => ContainerLimit.count,
      :container_limit_item          => ContainerLimitItem.count,
      :container_node                => ContainerNode.count,
      :container_port_config         => ContainerPortConfig.count,
      :container_project             => ContainerProject.count,
      :container_quota               => ContainerQuota.count,
      :container_quota_item          => ContainerQuotaItem.count,
      :container_replicator          => ContainerReplicator.count,
      :container_route               => ContainerRoute.count,
      :container_service             => ContainerService.count,
      :container_service_port_config => ContainerServicePortConfig.count,
      :container_template            => ContainerTemplate.count,
      :container_template_parameter  => ContainerTemplateParameter.count,
      :container_volume              => ContainerVolume.count,
      :custom_attribute              => CustomAttribute.count,
      :ext_management_system         => ExtManagementSystem.count,
      :hardware                      => Hardware.count,
      :operating_system              => OperatingSystem.count,
      :persistent_volume_claim       => PersistentVolumeClaim.count,
      :security_context              => SecurityContext.count,
    }

    expect(actual).to eq counts
  end

  def assert_ems
    expect(@ems).to have_attributes(
      :port => 8443,
      :type => "ManageIQ::Providers::Kubernetes::ContainerManager"
    )
  end

  def assert_specific_container
    @container = Container.find_by(:name => "stress4")
    expect(@container).to have_attributes(
      :name          => "stress4",
      :restart_count => 0,
    )
    expect(@container[:backing_ref]).not_to be_nil

    # Check the relation to container node
    expect(@container.container_group).to have_attributes(
      :name => "stress4-1-7r2fb"
    )

    # TODO: move to kubernetes refresher test (needs cassette containing seLinuxOptions)
    expect(@container.security_context).to have_attributes(
      :se_linux_user  => nil,
      :se_linux_role  => nil,
      :se_linux_type  => nil,
      :se_linux_level => "s0:c11,c10"
    )
  end

  def assert_specific_container_group
    @containergroup = ContainerGroup.find_by(:name => "stress4-1-7r2fb")
    expect(@containergroup).to have_attributes(
      :name           => "stress4-1-7r2fb",
      :restart_policy => "Always",
      :dns_policy     => "ClusterFirst",
    )

    # Check the relation to container node
    expect(@containergroup.container_node).to have_attributes(
      :name => "ladislav-ocp-3.6-compute04.10.35.49.24.nip.io"
    )

    # Check the relation to containers
    expect(@containergroup.containers.count).to eq(1)
    expect(@containergroup.containers.last).to have_attributes(
      :name => "stress4"
    )

    expect(@containergroup.container_project).to eq(ContainerProject.find_by(:name => "vcr-tests"))
    expect(@containergroup.ext_management_system).to eq(@ems)
  end

  def assert_specific_container_node
    @containernode = ContainerNode.find_by(:name => "ladislav-ocp-3.6-compute04.10.35.49.24.nip.io")
    expect(@containernode).to have_attributes(
      :name          => "ladislav-ocp-3.6-compute04.10.35.49.24.nip.io",
      :lives_on_type => nil,
      :lives_on_id   => nil
    )

    expect(@containernode.ext_management_system).to eq(@ems)
  end

  def assert_specific_container_services
    expect(ContainerService.count).to eq 0
  end

  def assert_specific_container_image_registry
    @registry = ContainerImageRegistry.find_by(:name => "docker.io")
    expect(@registry).to have_attributes(
      :name => "docker.io",
      :host => "docker.io",
      :port => nil
    )
    expect(@registry.container_services.count).to eq(0)
  end

  def assert_specific_container_project
    @container_pr = ContainerProject.find_by(:name => "vcr-tests")
    expect(@container_pr).to have_attributes(
      :name         => "vcr-tests",
      :display_name => nil,
    )

    expect(@container_pr.container_groups.count).to eq(2)
    expect(@container_pr.containers.count).to eq(2)
    expect(@container_pr.container_replicators.count).to eq(0)
    expect(@container_pr.container_routes.count).to eq(0)
    expect(@container_pr.container_services.count).to eq(0)
    expect(@container_pr.container_builds.count).to eq(0)
    expect(ContainerBuildPod.where(:namespace => @container_pr.name).count).to eq(0)
    expect(@container_pr.ext_management_system).to eq(@ems)
  end

  def assert_specific_container_route
    expect(ContainerRoute.count).to eq 0
  end

  def assert_specific_container_build
    expect(ContainerBuild.count).to eq 0
  end

  def assert_specific_container_build_pod
    expect(ContainerBuildPod.count).to eq 0
  end

  def assert_specific_container_template
    expect(ContainerTemplate.count).to eq 0
  end

  def assert_specific_used_container_image(metadata:)
    # An image mentioned both in /pods and /images, built by openshift so it has metadata.
    @container_image = ContainerImage.find_by(:name => "fsimonce/stress-test")

    expect(@container_image.ext_management_system).to eq(@ems)
    expect(@container_image.environment_variables.count).to eq(metadata ? 0 : 0)
    # TODO: for next recording, oc label some running, openshift-built image
    expect(@container_image.labels.count).to eq(0)
    expect(@container_image.docker_labels.count).to eq(metadata ? 0 : 0)
  end
end

describe ManageIQ::Providers::Kubernetes::ContainerManager::Refresher do
  context "graph refresh" do
    before(:each) do
      stub_settings_merge(
        :ems_refresh => {:kubernetes => {:inventory_object_refresh => true}}
      )

      expect(ManageIQ::Providers::Kubernetes::ContainerManager::RefreshParser).not_to receive(:ems_inv_to_hashes)
    end

    context "with :default saver" do
      before(:each) do
        stub_settings_merge(
          :ems_refresh => {:kubernetes => {:inventory_collections => {:saver_strategy => :default}}}
        )
      end

      include_examples "openshift refresher VCR targeted refresh tests"
    end

    context "with :batch saver" do
      before(:each) do
        stub_settings_merge(
          :ems_refresh => {:kubernetes => {:inventory_collections => {:saver_strategy => :batch}}}
        )
      end

      include_examples "openshift refresher VCR targeted refresh tests"
    end
  end
end
