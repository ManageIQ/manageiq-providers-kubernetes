autoload(:Kubeclient, 'kubeclient')

describe ManageIQ::Providers::Kubernetes::Inventory::Collector::WatchNotice do
  let(:ems)       { FactoryBot.create(:ems_kubernetes) }
  let(:collector) { ManageIQ::Providers::Kubernetes::Inventory::Collector::WatchNotice.new(ems, notices) }
  let(:service1)  { Kubeclient::Resource.new(:kind => "Service", :metadata => {:name => "app1", :namespace => "default"}) }
  let(:service2)  { Kubeclient::Resource.new(:kind => "Service", :metadata => {:name => "app2", :namespace => "default"}) }
  let(:endpoint1) { Kubeclient::Resource.new(:kind => "Endpoint", :metadata => {:name => "app1", :namespace => "default"}) }
  let(:endpoint2) { Kubeclient::Resource.new(:kind => "Endpoint", :metadata => {:name => "app2", :namespace => "default"}) }
  let(:notices)   { [] }

  context "with no notices" do
    it "#endpoints" do
      expect(collector.endpoints).to be_empty
    end

    it "#services" do
      expect(collector.services).to be_empty
    end
  end

  context "with a service notice" do
    let(:service_notice)  { Kubeclient::Resource.new(:type => "MODIFIED", :object => service1) }
    let(:notices)         { [service_notice] }

    it "#endpoints" do
      kubeclient = double("Kubeclient::Client")
      expect(ems).to receive(:connect).and_return(kubeclient)
      expect(kubeclient).to receive(:get_endpoint).with("app1", "default").and_return(endpoint1)

      expect(collector.endpoints).to include(endpoint1)
    end

    it "#services" do
      expect(collector.services).to include(service1)
    end
  end

  context "with an endpoint notice" do
    let(:endpoint_notice) { Kubeclient::Resource.new(:type => "MODIFIED", :object => endpoint1) }
    let(:notices)         { [endpoint_notice] }

    it "#services" do
      kubeclient = double("Kubeclient::Client")
      expect(ems).to receive(:connect).and_return(kubeclient)
      expect(kubeclient).to receive(:get_service).with("app1", "default").and_return(service1)

      expect(collector.services).to include(service1)
    end

    it "#endpoints" do
      expect(collector.endpoints).to include(endpoint1)
    end
  end

  context "with an endpoint and a service with the same name and namespace" do
    let(:service_notice)  { Kubeclient::Resource.new(:type => "MODIFIED", :object => service1) }
    let(:endpoint_notice) { Kubeclient::Resource.new(:type => "MODIFIED", :object => endpoint1) }
    let(:notices)         { [service_notice, endpoint_notice] }

    it "#endpoints" do
      expect(collector.endpoints).to include(endpoint1)
    end

    it "#services" do
      expect(collector.services).to include(service1)
    end
  end

  context "with different endpoint and service notices" do
    let(:service_notice)  { Kubeclient::Resource.new(:type => "MODIFIED", :object => service1) }
    let(:endpoint_notice) { Kubeclient::Resource.new(:type => "MODIFIED", :object => endpoint2) }
    let(:notices)         { [service_notice, endpoint_notice] }

    it "#endpoints" do
      kubeclient = double("Kubeclient::Client")
      expect(ems).to receive(:connect).and_return(kubeclient)
      expect(kubeclient).to receive(:get_endpoint).with("app1", "default").and_return(endpoint1)

      expect(collector.endpoints).to include(endpoint1, endpoint2)
    end

    it "#services" do
      kubeclient = double("Kubeclient::Client")
      expect(ems).to receive(:connect).and_return(kubeclient)
      expect(kubeclient).to receive(:get_service).with("app2", "default").and_return(service2)

      expect(collector.services).to include(service1, service2)
    end
  end
end
