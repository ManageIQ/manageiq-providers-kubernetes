describe ManageIQ::Providers::Kubernetes::ContainerManager::ContainerGroup do
  let(:ems) { FactoryBot.create(:ems_kubernetes) }
  let(:project) { FactoryBot.create(:container_project, :name => "test-project", :ext_management_system => ems) }
  let(:container_group) do
    FactoryBot.create(
      :kubernetes_container_group,
      :name                  => "test-pod",
      :ext_management_system => ems,
      :container_project     => project
    )
  end

  context "supports(:logs)" do
    it "supports logs when associated with an EMS and project" do
      expect(container_group.supports?(:logs)).to be_truthy
    end

    it "does not support logs when the pod is archived" do
      container_group.update!(:deleted_on => Time.now.utc)
      expect(container_group.supports?(:logs)).to be_falsey
      expect(container_group.unsupported_reason(:logs)).to include("no longer active")
    end

    it "does not support logs when EMS is missing" do
      container_group.ext_management_system = nil
      expect(container_group.supports?(:logs)).to be_falsey
      expect(container_group.unsupported_reason(:logs)).to include("not associated with an active provider")
    end

    it "does not support logs when project is missing" do
      container_group.container_project = nil
      expect(container_group.supports?(:logs)).to be_falsey
      expect(container_group.unsupported_reason(:logs)).to include("not associated with a project")
    end
  end

  context "#logs_queue" do
    let(:user) { FactoryBot.create(:user) }

    it "enqueues logs via MiqTask.generic_action_with_callback" do
      task_id = container_group.logs_queue(user.userid, :tail_lines => 100, :container => "web")

      task = MiqTask.find(task_id)
      expect(task.name).to eq("Fetching logs for Pod test-pod")
      expect(task.userid).to eq(user.userid)

      queue_item = MiqQueue.find_by(:miq_task_id => task_id)
      expect(queue_item.class_name).to eq(container_group.class.name)
      expect(queue_item.instance_id).to eq(container_group.id)
      expect(queue_item.method_name).to eq("logs")
      expect(queue_item.args).to eq([{:tail_lines => 100, :container => "web", :task_id => task_id}])
      expect(queue_item.role).to eq("ems_operations")
      expect(queue_item.zone).to eq(container_group.my_zone)
    end

    it "raises MiqException::Error when logs are not supported" do
      container_group.ext_management_system = nil
      expect { container_group.logs_queue(user.userid) }.to raise_error(MiqException::Error, /not associated with an active provider/)
    end
  end

  context "#raw_logs" do
    let(:kubeclient) { double("kubeclient") }
    let(:response) { double("response", :body => "log output line 1\nlog output line 2") }

    before do
      allow(ems).to receive(:connect).with(:service => "kubernetes").and_return(kubeclient)
    end

    it "fetches logs using provided container name" do
      expect(kubeclient).to receive(:get_pod_log)
        .with("test-pod", "test-project", :container => "web", :tail_lines => 50)
        .and_return(response)

      expect(container_group.raw_logs(:container => "web", :tail_lines => 50)).to eq("log output line 1\nlog output line 2")
    end

    it "defaults container to first container if not specified" do
      FactoryBot.create(:container, :name => "first-container", :container_group => container_group)

      expect(kubeclient).to receive(:get_pod_log)
        .with("test-pod", "test-project", :container => "first-container")
        .and_return(response)

      expect(container_group.raw_logs).to eq("log output line 1\nlog output line 2")
    end

    it "filters out unsupported options" do
      expect(kubeclient).to receive(:get_pod_log)
        .with("test-pod", "test-project", :container => "web", :tail_lines => 10)
        .and_return(response)

      expect(container_group.raw_logs(:container => "web", :tail_lines => 10, :malicious_arg => "bad")).to eq("log output line 1\nlog output line 2")
    end
  end
end
