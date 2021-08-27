describe ManageIQ::Providers::Kubernetes::ContainerManager::RefreshWorker::WatchThread do
  let(:ems)              { FactoryBot.create(:ems_kubernetes) }
  let(:queue)            { Queue.new }
  let(:resource_version) { nil }
  let(:entity_type)      { nil }
  let(:watch_thread)     { described_class.new({}, ems.class, queue, entity_type, resource_version) }

  describe "#noop? (private)" do
    require "kubeclient"
    let(:notice)      { Kubeclient::Resource.new(:type => "MODIFIED", :object => object) }
    let(:entity_type) { :endpoints }

    context "endpoints without subsets" do
      let(:object) { Kubeclient::Resource.new(:kind => "Endpoints", :metadata => {:name => "app1", :namespace => "default"}) }

      it "skips update" do
        expect(watch_thread.send(:noop?, notice)).to be_truthy
      end
    end

    context "endpoints with subsets" do
      let(:object) { Kubeclient::Resource.new(:kind => "Endpoints", :subsets => [{}], :metadata => {:name => "app1", :namespace => "default"}) }

      it "doesn't skip update" do
        expect(watch_thread.send(:noop?, notice)).to be_falsey
      end
    end
  end
end
