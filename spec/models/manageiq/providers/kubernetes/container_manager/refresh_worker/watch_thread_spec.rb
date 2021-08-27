describe ManageIQ::Providers::Kubernetes::ContainerManager::RefreshWorker::WatchThread do
  require "kubeclient"

  let(:ems)              { FactoryBot.create(:ems_kubernetes) }
  let(:queue)            { Queue.new }
  let(:resource_version) { "1" }
  let(:entity_type)      { nil }
  let(:notice)           { Kubeclient::Resource.new(:type => "MODIFIED", :object => object) }
  let(:watch_thread)     { described_class.new({}, ems.class, queue, entity_type, resource_version) }

  describe "#collector_thread (private)" do
    let(:entity_type) { :pods }
    let(:connection)  { double("Kubeclient::Client") }
    let(:watch)       { double("Kubeclient::Common::WatchStream") }
    let(:object)      { Kubeclient::Resource.new(:kind => "Pod", :metadata => {:name => "pod-696ddc596b-qs64c", :namespace => "default", :resourceVersion => "2"}) }

    before do
      allow(watch_thread).to receive(:running?).and_return(true, false)
      allow(watch_thread).to receive(:connection).with(entity_type).and_return(connection)

      allow(connection)
        .to receive(:send)
        .with("watch_#{entity_type}", :resource_version => resource_version)
        .and_return(watch)

      allow(watch).to receive(:each).and_yield(notice).once
    end

    it "queues a notice" do
      watch_thread.send(:collector_thread)

      expect(queue.length).to eq(1)
      expect(queue.pop).to    eq(notice)
    end

    it "updates the last resource_version" do
      expect(watch_thread).to receive(:resource_version=).with("2")

      watch_thread.send(:collector_thread)
    end

    context "410 Gone" do
      let(:object) { Kubeclient::Resource.new(:kind => "Status", :code => 410, :reason => "Gone") }
      let(:notice) { Kubeclient::Resource.new(:type => "ERROR", :object => object) }

      it "restarts the watch from the start" do
        expect(watch_thread).to receive(:resource_version=).with(nil)

        watch_thread.send(:collector_thread)
      end
    end

    context "401 Unauthorized" do
      before do
        expect(watch).to receive(:each).and_raise(Kubeclient::HttpError.new(401, "Unauthorized", "Unauthorized"))
      end

      it "restarts the watch from the last resource_version" do
        expect(connection)
          .to receive(:send)
          .twice
          .with("watch_#{entity_type}", :resource_version => resource_version)
          .and_return(watch)

        watch_thread.send(:collector_thread)
      end
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
