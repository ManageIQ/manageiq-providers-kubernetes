require 'kubeclient'
require 'recursive-open-struct'
require_relative '../../../workers/event_catcher/event_parser'
require_relative '../../../lib/manageiq/providers/kubernetes/workers/event_catcher_base'

RSpec.describe KubernetesEventCatcherBase do
  let(:ems)            { {'id' => 1, 'type' => 'ManageIQ::Providers::Kubernetes::ContainerManager', 'ems_type' => 'kubernetes'} }
  let(:endpoint)       { {'hostname' => 'localhost'} }
  let(:authentication) { {'auth_key' => 'test-token'} }
  let(:settings)       { {'ems' => {'ems_kubernetes' => {'blacklisted_event_names' => []}}} }
  let(:logger)         { instance_double('Logger', :info => nil, :warn => nil) }

  let(:subclass) do
    Class.new(described_class) do
      def auth_options
        {:bearer_token => 'overridden-token'}
      end

      def log_prefix
        'MIQ(TestSubclass::EventCatcher)'
      end
    end
  end

  subject(:base_catcher) do
    described_class.new(ems, endpoint, authentication, settings, {}, logger)
  end

  subject(:sub_catcher) do
    subclass.new(ems, endpoint, authentication, settings, {}, logger)
  end

  describe '#auth_options' do
    context 'default implementation' do
      it 'returns bearer_token from authentication auth_key' do
        expect(base_catcher.send(:auth_options)).to eq(:bearer_token => 'test-token')
      end

      it 'returns username/password when userid and password are present' do
        catcher = described_class.new(
          ems, endpoint,
          {'userid' => 'user', 'password' => 'pass'},
          settings, {}, logger
        )
        expect(catcher.send(:auth_options)).to include(:username => 'user', :password => 'pass')
      end

      it 'returns an empty hash when authentication is empty' do
        catcher = described_class.new(ems, endpoint, {}, settings, {}, logger)
        expect(catcher.send(:auth_options)).to eq({})
      end
    end

    context 'subclass override' do
      it 'returns the overridden auth_options' do
        expect(sub_catcher.send(:auth_options)).to eq(:bearer_token => 'overridden-token')
      end
    end
  end

  describe '#build_client' do
    let(:kubeclient) { double('Kubeclient::Client', :discover => nil) }

    it 'passes auth_options from the default implementation into Kubeclient' do
      expect(Kubeclient::Client).to receive(:new) do |_url, _version, opts|
        expect(opts[:auth_options]).to eq(:bearer_token => 'test-token')
        kubeclient
      end
      base_catcher.send(:build_client)
    end

    it 'passes the subclass-overridden auth_options into Kubeclient' do
      expect(Kubeclient::Client).to receive(:new) do |_url, _version, opts|
        expect(opts[:auth_options]).to eq(:bearer_token => 'overridden-token')
        kubeclient
      end
      sub_catcher.send(:build_client)
    end

    it 'calls auth_options exactly once per build_client call' do
      allow(Kubeclient::Client).to receive(:new).and_return(kubeclient)
      expect(base_catcher).to receive(:auth_options).once.and_call_original
      base_catcher.send(:build_client)
    end
  end

  describe '#log_prefix' do
    it 'returns the default Kubernetes prefix for the base class' do
      expect(base_catcher.send(:log_prefix)).to include('Kubernetes')
    end

    it 'returns the subclass-defined prefix when overridden' do
      expect(sub_catcher.send(:log_prefix)).to eq('MIQ(TestSubclass::EventCatcher)')
    end
  end
end
