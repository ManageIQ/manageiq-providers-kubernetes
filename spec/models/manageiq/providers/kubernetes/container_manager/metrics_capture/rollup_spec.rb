# instantiated at the end, for both classical and graph refresh
shared_examples "kubernetes rollup tests" do
  before(:each) do
    _guid, _server, _zone = EvmSpecHelper.create_guid_miq_server_zone
    TimeProfile.seed # We need this to get TimeProfile for daily rollup
  end

  let(:ems) do
    hostname = 'capture.context.com'
    token = 'theToken'

    @ems = FactoryBot.create(
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
  end

  let(:container_project) do
    FactoryBot.create(:container_project, :ext_management_system => ems)
  end

  let(:container_node_a) do
    hardware = FactoryBot.create(:hardware,
                                  :cpu_total_cores => 10,
                                  :memory_mb       => 1024)

    node = FactoryBot.create(:container_node)

    hardware.update_attributes(:computer_system => node.computer_system)
    node
  end

  let(:container_node_b) do
    hardware = FactoryBot.create(:hardware,
                                  :cpu_total_cores => 2,
                                  :memory_mb       => 2048)

    node = FactoryBot.create(:container_node)

    hardware.update_attributes(:computer_system => node.computer_system)
    node
  end

  let(:container_group_10core_1GB) do
    FactoryBot.create(:container_group,
                       :container_project     => container_project,
                       :container_node        => container_node_a,
                       :ext_management_system => ems)
  end

  let(:container_group_2core_2GB) do
    FactoryBot.create(:container_group,
                       :container_project     => container_project,
                       :container_node        => container_node_b,
                       :ext_management_system => ems)
  end

  let(:container_image_a) do
    FactoryBot.create(:container_image,
                       :ext_management_system => ems,
                       :custom_attributes     => [custom_attribute_a])
  end

  let(:container_a) do
    FactoryBot.create(:container,
                       :name                  => "A",
                       :container_group       => container_group_10core_1GB,
                       :container_image       => container_image_a,
                       :ext_management_system => ems)
  end

  let(:custom_attribute_a) do
    FactoryBot.create(:custom_attribute,
                       :name    => 'com.redhat.component',
                       :value   => 'EAP7',
                       :section => 'docker_labels')
  end

  let(:container_b) do
    FactoryBot.create(:container,
                       :name                  => "B",
                       :container_group       => container_group_2core_2GB,
                       :container_image       => container_image_b,
                       :ext_management_system => ems)
  end

  let(:container_image_b) do
    FactoryBot.create(:container_image,
                       :ext_management_system => ems,
                       :custom_attributes     => [custom_attribute_b])
  end

  let(:custom_attribute_b) do
    FactoryBot.create(:custom_attribute,
                       :name    => 'com.redhat.component',
                       :value   => 'EAP7',
                       :section => 'docker_labels')
  end

  let(:start_time) { Time.parse('2012-09-01 00:00:00Z').utc }
  let(:end_time) { start_time + 1.day + 10.seconds }

  before do
    Timecop.travel(end_time)
  end

  after do
    Timecop.return
  end

  # TODO(lsmola) with 60s interval, we need also a spec for the fact that there can be 2 samples. Then if we take
  # pod1 using 100 cores only in <12:00:00, 12:00:30) and pod2 using 100 cores only in <12:00:30, 12:01:00). The
  # project avg should be 100 cores, not 200 cores.
  def add_metrics_for(resource, range, metric_params: {}, step: 60.seconds)
    range.step_value(step).each do |time|
      metric_params[:timestamp]           = time
      metric_params[:resource_id]         = resource.id
      metric_params[:resource_name]       = resource.name
      metric_params[:parent_ems_id]       = ems.id
      metric_params[:derived_vm_numvcpus] = resource.container_node.hardware.cpu_total_cores
      if metric_params[:mem_usage_absolute_average].to_i > 0
        metric_params[:derived_memory_used]      = (metric_params[:mem_usage_absolute_average] / 100.0) * resource.container_node.hardware.memory_mb
        metric_params[:derived_memory_available] = resource.container_node.hardware.memory_mb - metric_params[:derived_memory_used]
      end
      resource.metrics << FactoryBot.create(:metric, metric_params)
    end
  end

  def rollup_up_to_project(rollup_end_time = start_time + 2.hours)
    # Queue hourly rollups for all ContainerGroups
    ContainerGroup.all.each.each do |resource|
      resource.perf_rollup_to_parents('realtime', start_time, rollup_end_time)
    end

    # ContainerGroup hourly rollups
    MiqQueue.where(:class_name => "ContainerGroup", :method_name => "perf_rollup").map do |x|
      x.deliver
      x.destroy
    end

    # ContainerProject hourly rollups
    MiqQueue.where(:class_name => "ContainerProject", :method_name => "perf_rollup").map do |x|
      x.deliver
      x.destroy
    end
  end

  def assert_entities(project_rollup)
    expect(project_rollup.assoc_ids[:container_nodes][:on]).to(
      match_array([container_node_a.id, container_node_b.id])
    )
    expect(project_rollup.assoc_ids[:container_nodes][:off]).to(
      match_array([])
    )
    expect(project_rollup.assoc_ids[:container_groups][:on]).to(
      match_array([container_group_10core_1GB.id, container_group_2core_2GB.id])
    )
    expect(project_rollup.assoc_ids[:container_groups][:off]).to(
      match_array([])
    )
  end

  it "check project rollup can handle partial hour" do
    # Add 10 minutes of 50% cpu_util and mem util
    add_metrics_for(
      container_group_10core_1GB,
      start_time..(start_time + 10.minutes),
      :metric_params => {
        :cpu_usage_rate_average     => 50.0,
        :mem_usage_absolute_average => 50.0,
      }
    )

    # Add 10 minutes of 75% cpu_util and mem util
    add_metrics_for(
      container_group_2core_2GB,
      start_time..(start_time + 10.minutes),
      :metric_params => {
        :cpu_usage_rate_average     => 75.0,
        :mem_usage_absolute_average => 75.0,
      }
    )

    rollup_up_to_project
    project_rollup = MetricRollup.where(:resource => container_project, :timestamp => start_time, :capture_interval_name => "hourly").first

    # Check the Project rollup has the wanted elements
    assert_entities(project_rollup)

    # Right now we take the 10 minutes as the whole hour, so 75% of 2 cores, + 50% of 10 cores is 54.17% of 12 cores
    expected_cpu_util = (75 * 2 + 50 * 10) / 12.0
    expect(project_rollup.cpu_usage_rate_average.round(2)).to eq(expected_cpu_util.round(2))

    # And memory is also taken as if the pods were running full hour
    expect(project_rollup).to(
      have_attributes(
        :derived_memory_used        => 2048.0,
        :derived_vm_numvcpus        => 12.0,
        :derived_memory_available   => 3072.0,
        :mem_usage_absolute_average => 66.6666666666667
      )
    )

    # TODO(lsmola) Described in https://bugzilla.redhat.com/show_bug.cgi?id=1506671
    pending("We need to store also actual usage, with only 10.minutes running, the usage should be divided by 6")
    expect(project_rollup.cpu_usage_rate_average.round(2)).to eq((expected_cpu_util / 6).round(2))
    expect(project_rollup.derived_memory_used).to eq(2048 / 6.0)
  end

  it "checks pods running sequentially are not being multiplicated in project rollup" do
    # Add 10 minutes of 100% cpu_util and mem util
    add_metrics_for(
      container_group_10core_1GB,
      start_time..(start_time + 10.minutes),
      :metric_params => {
        :cpu_usage_rate_average     => 100.0,
        :mem_usage_absolute_average => 100.0,
      }
    )

    # then the pod a is killed and have another add 10 minutes of 100% cpu_util and mem util
    add_metrics_for(
      container_group_2core_2GB,
      (start_time + 10.minutes)..(start_time + 20.minutes),
      :metric_params => {
        :cpu_usage_rate_average     => 100.0,
        :mem_usage_absolute_average => 100.0,
      }
    )

    rollup_up_to_project
    project_rollup = MetricRollup.where(:resource => container_project, :timestamp => start_time, :capture_interval_name => "hourly").first

    # Check the Project rollup has the wanted elements
    assert_entities(project_rollup)

    expect(project_rollup).to(
      have_attributes(
        :cpu_usage_rate_average     => 100.0,
        :derived_memory_used        => 3072.0,
        :derived_vm_numvcpus        => 12.0,
        :derived_memory_available   => 3072.0,
        :mem_usage_absolute_average => 100.0
      )
    )

    # TODO(lsmola) A side effect of https://bugzilla.redhat.com/show_bug.cgi?id=1506671, since we take short usage
    # as usage of the whole hour, then Project rollups based on those rollups will be also wrong.
    # TODO(lsmola) the main thing is that we will report project breaching it's quota. E.g if the project quota was
    # 2048MB ram and 10 cores, this scenario was ok, since max usage was never higher. But we report that the usage
    # was 3072MB and 12 cores.
    pending("Right now we ignore, that the sub hour usage was sequential, so the Project rollup can go above possible quota")
    # We had 10 cores on 100% for 10 minutes(1/6 of hour), then 2 cores on 100% for 10 minutes
    expected_cpu_util = 10 / 6.0 + 2 / 6.0 # that is 2 cores avg used in 1h, 10 cores max in 1 hour
    expected_cpu_util = (expected_cpu_util / 10.0) * 100 # So only 20% of the 10 cores were used in avg
    expect(project_rollup.cpu_usage_rate_average).to eq(expected_cpu_util)
    # There was max 10 cores in use in simultaneously, but this should be really the project quota, since that is the
    # 100%
    expect(project_rollup.derived_vm_numvcpus).to eq(10)
    # We had 2048MB for 10 minutes then 1024MB for 10 minutes
    expected_memory = 2048 / 6.0 + 1024 / 6.0 # So only 512MB were used in avg, and 2048 max
    expect(project_rollup.derived_memory_used).to eq(expected_memory)
  end

  it "daily project rollup computes correctly when metrics are missing" do
    # Add 10 minutes of 100% cpu_util and mem util
    add_metrics_for(
      container_group_10core_1GB,
      start_time..(start_time + 10.minutes),
      :metric_params => {
        :cpu_usage_rate_average     => 100.0,
        :mem_usage_absolute_average => 100.0,
      }
    )

    # Add 10 minutes of 100% cpu_util and mem util
    add_metrics_for(
      container_group_2core_2GB,
      start_time..(start_time + 10.minutes),
      :metric_params => {
        :cpu_usage_rate_average     => 100.0,
        :mem_usage_absolute_average => 100.0,
      }
    )

    rollup_up_to_project(start_time + 1.day)
    # Do also Project daily rollup
    MiqQueue.where(:class_name => "ContainerProject", :method_name => :perf_rollup).all.map(&:deliver)

    project_daily_rollup = MetricRollup.where(:resource => container_project, :timestamp => start_time, :capture_interval_name => "daily").first

    # We had 1 hour on 100% of 12 cores, then we had no metrics. So 100% divided by 24 hours, same for memory
    expect(project_daily_rollup.cpu_usage_rate_average.round(2)).to eq((100 / 24.0).round(2))
    expect(project_daily_rollup.derived_memory_used).to eq(3072 / 24.0)
    expect(project_daily_rollup.derived_vm_numvcpus).to eq(12 / 24.0)

    # Min/Max values are correct, given we take min/max of hourly rollups
    expect(project_daily_rollup.min_max[:max_cpu_usage_rate_average]).to eq(100)
    expect(project_daily_rollup.min_max[:min_cpu_usage_rate_average]).to eq(0)
    expect(project_daily_rollup.min_max[:max_derived_vm_numvcpus]).to eq(12)
    expect(project_daily_rollup.min_max[:min_derived_vm_numvcpus]).to eq(0)
    expect(project_daily_rollup.min_max[:max_derived_memory_used]).to eq(3072)
    expect(project_daily_rollup.min_max[:min_derived_memory_used]).to eq(0)

    # TODO(lsmola) the problematic part is that we take :derived_vm_numvcpus from the Metrics, so when there are no
    # metrics, the derived_vm_numvcpus is 0
    # Example:
    # So having 1h of 12 cores on 100%, then nothing. That should mean the daily usage was 12 cores/24h.
    # So 0.5 core in average. Using percents, the max amount should be the project quota, so if the quota was 12cores
    # we would have 100%/24 of 12 cores. That is again 0.5core (of course the quota can change in time, so it needs to
    # be hourly quota)
    #
    # Bad result:
    # Since when there are no metrics, only the 1 hourly rollups says it has derived_vm_numvcpus 12 cores. The other
    # report 0. So then the average we are doing is also making average of the derived_vm_numvcpus. That is 1 time 12
    # and 23 times 0 derived_vm_numvcpus.
    # So the reports ends up saying that the daily project usage was 100% / 24h of 12 cores / 24h. So the result is
    # 24x smaller than expected. So not 0.5 core avg used in a day, but 0.5/24.0 core avg used in a day.
    #
    # The reason of bad result is the same as for the spec with present metrics, we keep this as placeholder for having
    # quotas as the maximums, so the percentages make sense.
    pending("We should use quotas as a max derived_vm_numvcpus for project")
    expect(project_daily_rollup.derived_vm_numvcpus).to eq(12)
  end

  it "daily project rollup computes correctly when metrics are present" do
    # Add 10 minutes of 100% cpu_util and mem util
    add_metrics_for(
      container_group_10core_1GB,
      start_time..(start_time + 10.minutes),
      :metric_params => {
        :cpu_usage_rate_average     => 100.0,
        :mem_usage_absolute_average => 100.0,
      }
    )

    # Add 10 minutes of 100% cpu_util and mem util
    add_metrics_for(
      container_group_2core_2GB,
      start_time..(start_time + 10.minutes),
      :metric_params => {
        :cpu_usage_rate_average     => 100.0,
        :mem_usage_absolute_average => 100.0,
      }
    )

    # Add rest of the day as 50% cpu_util and mem util
    (start_time + 1.hour..start_time + 1.day).step_value(1.hour).each do |time|
      add_metrics_for(
        container_group_2core_2GB,
        time..(time + 10.minutes),
        :metric_params => {
          :cpu_usage_rate_average     => 50.0,
          :mem_usage_absolute_average => 50.0,
        }
      )
    end

    rollup_up_to_project(start_time + 1.day)
    # Do also Project daily rollup

    MiqQueue.where(:class_name => "ContainerProject", :method_name => :perf_rollup).all.map(&:deliver)

    project_daily_rollup = MetricRollup.where(:resource => container_project, :timestamp => start_time, :capture_interval_name => "daily").first

    # We had 1 hour on 100% of 12 cores, then we had 50% for the rest 23h. Same for memory
    expect(project_daily_rollup.cpu_usage_rate_average.round(2)).to eq(((100 + 23 * 50) / 24.0).round(2))
    expect(project_daily_rollup.derived_memory_used.round(2)).to eq(((3072 + 23 * 1024) / 24.0).round(2))
    expect(project_daily_rollup.derived_vm_numvcpus.round(2)).to eq(((12 + 23 * 2) / 24.0).round(2))

    # Min/Max values are correct, given we take min/max of hourly rollups
    expect(project_daily_rollup.min_max[:max_cpu_usage_rate_average]).to eq(100)
    expect(project_daily_rollup.min_max[:min_cpu_usage_rate_average]).to eq(50)
    expect(project_daily_rollup.min_max[:max_derived_vm_numvcpus]).to eq(12)
    expect(project_daily_rollup.min_max[:min_derived_vm_numvcpus]).to eq(2)
    expect(project_daily_rollup.min_max[:max_derived_memory_used]).to eq(3072)
    expect(project_daily_rollup.min_max[:min_derived_memory_used]).to eq(1024)

    # TODO(lsmola) so, problem is that for daily, we do a normal average, instead of the weighted average for %
    # https://github.com/Ladas/manageiq/blob/27abccad510b78b0e0e024c5a5d2117ed05fcca5/app/models/vim_performance_daily.rb#L55
    # While for hourly we are doing correct weighted average
    # https://github.com/Ladas/manageiq/blob/6150a4cac10c7ad76acddb448bb3039486ff32ca/app/models/metric/aggregation.rb#L42
    # So that will lead to wrong value.
    # Example:
    # Here the 1st hour consumes 12 cores(of 12 total, so 100%), then each of the rest 23hours consumes 1 core (of 2 total, so 50%)
    #
    # Expected result:
    # So average daily usage must be (12 + (23 * 1)) / 24.0 == 1.46 core.
    # derived_vm_numvcpus: (12 + (23 * 2)) / 24.0 == 2.42 core
    # cpu_usage_rate_average: 100 / ((12 + (23 * 2)) / 24.0) * ((12 + (23 * 1)) / 24.0) == 60.34% !!!
    #
    # Bad result:
    # But we are seeing
    # derived_vm_numvcpus: ((12 + 23*2) / 24.0) == 2.42 core, so this is correct
    # cpu_usage_rate_average: ((100 + 23*50) / 24.0) == 52.08% (so just a simple avg of summed percent?!!!)
    #
    # So what is the correct weighted average:
    # 100.0 / ((12 + 23*2)) * ((100*12 + 23*50*2) / 100.0 ) == 60.34% (this is how we compute it in Metric::Aggregation::Aggregate.column)
    # so it's 100% / (58 cores total) * (12+23 == 35cores used) == 60.34% of cores used
    pending("We have to use weighted averages also for daily rollup, if we doing average of % values, with different bases")
    expect(project_daily_rollup.cpu_usage_rate_average.round(2)).to eq((100.0 / 58 * 35).round(2))
  end
end

describe ManageIQ::Providers::Kubernetes::ContainerManager::Refresher do
  include_examples "kubernetes rollup tests"
end
