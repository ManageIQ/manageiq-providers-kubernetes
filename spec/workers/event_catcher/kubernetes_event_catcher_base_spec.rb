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

    it 'resets @token_expiry to nil before calling auth_options' do
      allow(Kubeclient::Client).to receive(:new).and_return(kubeclient)
      base_catcher.instance_variable_set(:@token_expiry, Time.now.utc + 3600)
      base_catcher.send(:build_client)
      expect(base_catcher.instance_variable_get(:@token_expiry)).to be_nil
    end

    it 'passes cert_store built from certificate_authority PEM in ssl_options when present' do
      key  = OpenSSL::PKey::RSA.new(2048)
      cert = OpenSSL::X509::Certificate.new
      cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/CN=test-ca')
      cert.not_before = Time.now.utc
      cert.not_after  = Time.now.utc + 3600
      cert.public_key = key.public_key
      cert.serial     = 1
      cert.version    = 2
      cert.sign(key, OpenSSL::Digest::SHA256.new)
      pem = cert.to_pem
      catcher = described_class.new(
        ems,
        endpoint.merge('certificate_authority' => pem),
        authentication, settings, {}, logger
      )
      expect(Kubeclient::Client).to receive(:new) do |_url, _version, opts|
        expect(opts[:ssl_options][:cert_store]).to be_an(OpenSSL::X509::Store)
        expect(opts[:ssl_options][:ca_file]).to be_nil
        kubeclient
      end
      catcher.send(:build_client)
    end

    it 'loads all certs from a PEM chain into the cert_store' do
      # Build two distinct self-signed certs to simulate an intermediate + root chain
      certs = 2.times.map do |i|
        key  = OpenSSL::PKey::RSA.new(2048)
        cert = OpenSSL::X509::Certificate.new
        cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/CN=test-ca-#{i}")
        cert.not_before = Time.now.utc
        cert.not_after  = Time.now.utc + 3600
        cert.public_key = key.public_key
        cert.serial     = i + 1
        cert.version    = 2
        cert.sign(key, OpenSSL::Digest::SHA256.new)
        cert
      end
      chain_pem = certs.map(&:to_pem).join
      catcher = described_class.new(
        ems,
        endpoint.merge('certificate_authority' => chain_pem),
        authentication, settings, {}, logger
      )
      expect(Kubeclient::Client).to receive(:new) do |_url, _version, opts|
        store = opts[:ssl_options][:cert_store]
        expect(store).to be_an(OpenSSL::X509::Store)
        # Both certs must be trusted by the store
        certs.each { |cert| expect(store.verify(cert)).to be(true) }
        kubeclient
      end
      catcher.send(:build_client)
    end

    it 'passes nil cert_store when certificate_authority is absent' do
      captured_opts = nil
      allow(Kubeclient::Client).to receive(:new) do |_url, _version, opts|
        captured_opts = opts
        kubeclient
      end
      base_catcher.send(:build_client)
      expect(captured_opts[:ssl_options][:cert_store]).to be_nil
    end
  end

  describe '#token_expiry' do
    it 'returns nil by default so no timer is scheduled for long-lived tokens' do
      expect(base_catcher.send(:token_expiry)).to be_nil
    end

    it 'can be overridden by a subclass to return a future Time' do
      expiry = Time.now.utc + 3600
      subclass_with_expiry = Class.new(described_class) do
        define_method(:token_expiry) { expiry }
      end
      catcher = subclass_with_expiry.new(ems, endpoint, authentication, settings, {}, logger)
      expect(catcher.send(:token_expiry)).to eq(expiry)
    end
  end

  describe '#schedule_token_refresh' do
    let(:watcher) { double('Kubeclient::Common::WatchStream') }

    it 'returns nil and spawns no thread when token_expiry is nil' do
      expect(Thread).not_to receive(:new)
      result = base_catcher.send(:schedule_token_refresh, watcher)
      expect(result).to be_nil
    end

    it 'returns a Thread when token_expiry is set' do
      allow(base_catcher).to receive(:token_expiry).and_return(Time.now.utc + 3600)
      allow(watcher).to receive(:finish)
      thread = base_catcher.send(:schedule_token_refresh, watcher)
      expect(thread).to be_a(Thread)
      thread.kill
    end

    it 'schedules the timer at 90% of the remaining TTL' do
      now    = Time.now.utc
      expiry = now + 1000
      allow(Time).to receive(:now).and_return(now)

      # 90% of 1000s TTL = 900s delay
      expect(base_catcher.send(:token_refresh_delay, expiry)).to be_within(0.001).of(900)
    end

    it 'clamps delay to 0 when token is already expired' do
      allow(base_catcher).to receive(:token_expiry).and_return(Time.now.utc - 10)
      allow(watcher).to receive(:finish)
      thread = base_catcher.send(:schedule_token_refresh, watcher)
      expect(thread).to be_a(Thread)
      thread.kill
    end
  end

  describe '#watch_events — token refresh integration' do
    let(:watcher) { double('Kubeclient::Common::WatchStream') }
    let(:client)  { double('Kubeclient::Client', :watch_events => watcher) }

    it 'kills the timer thread after watch completes normally' do
      timer = instance_double(Thread)
      allow(base_catcher).to receive(:schedule_token_refresh).and_return(timer)
      allow(watcher).to receive(:each)
      expect(timer).to receive(:kill)
      base_catcher.send(:watch_events, client, '1')
    end

    it 'kills the timer thread even when an EOFError is raised' do
      timer = instance_double(Thread)
      allow(base_catcher).to receive(:schedule_token_refresh).and_return(timer)
      allow(watcher).to receive(:each).and_raise(EOFError)
      expect(timer).to receive(:kill)
      base_catcher.send(:watch_events, client, '1')
    end

    it 'rescues Kubeclient::HttpError, logs a reconnect message, and returns the current version' do
      allow(base_catcher).to receive(:schedule_token_refresh).and_return(nil)
      allow(watcher).to receive(:each).and_raise(Kubeclient::HttpError.new(401, 'Unauthorized', nil))
      expect(logger).to receive(:warn).with(/reconnecting/)
      expect(base_catcher.send(:watch_events, client, '77')).to eq('77')
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
