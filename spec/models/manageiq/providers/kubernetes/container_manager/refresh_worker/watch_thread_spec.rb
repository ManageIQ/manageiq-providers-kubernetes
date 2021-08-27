describe ManageIQ::Providers::Kubernetes::ContainerManager::RefreshWorker::WatchThread do
  require "kubeclient"

  let(:ems)              { FactoryBot.create(:ems_kubernetes) }
  let(:queue)            { Queue.new }
  let(:resource_version) { nil }
  let(:entity_type)      { nil }
  let(:notice)           { Kubeclient::Resource.new(:type => "MODIFIED", :object => object) }
  let(:watch_thread)     { described_class.new({}, ems.class, queue, entity_type, resource_version) }

  describe "#collector_thread (private)" do
    let(:entity_type) { :pods }
    let(:connection)  { double("Kubeclient::Client") }
    let(:watch)       { double("Kubeclient::Common::WatchStream") }
    let(:object)      { Kubeclient::Resource.new(:kind => "Pod", :metadata => {:name => "pod-696ddc596b-qs64c", :namespace => "default", :resourceVersion => "2"}) }

    before do
      expect(watch_thread).to receive(:running?).and_return(true, false)
      expect(watch_thread).to receive(:connection).with(entity_type).and_return(connection)

      expect(connection)
        .to receive(:send)
        .with("watch_#{entity_type}", :resource_version => resource_version)
        .and_return(watch)

      expect(watch).to receive(:each).and_yield(notice).once
    end

    it "queues a notice" do
      watch_thread.send(:collector_thread)

      expect(queue.length).to eq(1)
      expect(queue.pop).to    eq(notice)
    end
  end

  describe "#noop? (private)" do
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
