require 'kubeclient'
require 'recursive-open-struct'
require_relative '../../../workers/event_catcher/event_parser'
require_relative '../../../workers/event_catcher/event_catcher'

RSpec.describe EventCatcher do
  let(:settings) { {'ems' => {'ems_kubernetes' => {'blacklisted_event_names' => []}}} }
  let(:logger) { instance_double('Logger', :info => nil, :warn => nil) }
  let(:catcher) do
    described_class.new({'id' => 1, 'type' => 'ManageIQ::Providers::Kubernetes::ContainerManager', 'ems_type' => 'kubernetes'}, {'hostname' => 'localhost'}, {}, settings, {}, logger)
  end

  def event(kind, reason)
    RecursiveOpenStruct.new(:object => {
                              :lastTimestamp  => 'now',
                              :involvedObject => {:kind => kind, :name => 'name', :uid => 'uid'},
                              :reason         => reason,
                              :metadata       => {:uid => 'event-uid'}
                            })
  end

  described_class::DISABLED_KINDS.each do |kind|
    it "filters #{kind} events (disabled kind)" do
      expect(catcher.send(:filtered?, EventParser.extract_event_data(event(kind, 'SomeReason')))).to be(true)
    end
  end

  it 'filters blacklisted events from scoped worker settings' do
    scoped_catcher = described_class.new({'id' => 1, 'type' => 'ManageIQ::Providers::Kubernetes::ContainerManager', 'ems_type' => 'kubernetes'}, {'hostname' => 'localhost'}, {}, {'blacklisted_event_names' => ['NODE_REBOOTED']}, {}, logger)
    expect(scoped_catcher.send(:filtered?, EventParser.extract_event_data(event('Node', 'Rebooted')))).to be(true)
  end

  it 'filters blacklisted events from full ems settings fallback' do
    settings['ems']['ems_kubernetes']['blacklisted_event_names'] = ['NODE_REBOOTED']
    expect(catcher.send(:filtered?, EventParser.extract_event_data(event('Node', 'Rebooted')))).to be(true)
  end

  it 'accepts non-disabled kind events with arbitrary reasons' do
    expect(catcher.send(:filtered?, EventParser.extract_event_data(event('Node', 'Unknown')))).to be(false)
    expect(catcher.send(:filtered?, EventParser.extract_event_data(event('Pod', 'CustomReason')))).to be(false)
    expect(catcher.send(:filtered?, EventParser.extract_event_data(event('Deployment', 'ScalingReplicaSet')))).to be(false)
  end

  describe '#watch_events' do
    let(:watcher) { double('Kubeclient::Common::WatchStream') }
    let(:client)  { double('Kubeclient::Client', :watch_events => watcher) }

    it 'returns the incoming version unchanged when the watcher yields no events' do
      allow(watcher).to receive(:each)
      expect(catcher.send(:watch_events, client, '42')).to eq('42')
    end

    it 'skips and logs events with no involvedObject without crashing' do
      bare_event = double('WatchEvent', :type => 'BOOKMARK')
      allow(EventParser).to receive(:extract_event_data).and_return({})
      allow(watcher).to receive(:each).and_yield(bare_event)
      expect(logger).to receive(:info).with(/Skipping event with no involvedObject/)
      expect(catcher.send(:watch_events, client, '42')).to eq('42')
    end

    it 'resets version to nil on an ERROR event so the outer loop re-fetches a fresh resourceVersion' do
      error_event = double('WatchEvent', :type => 'ERROR')
      allow(EventParser).to receive(:extract_event_data).and_return({})
      allow(watcher).to receive(:each).and_yield(error_event)
      allow(logger).to receive(:info).with(/Skipping event with no involvedObject/)
      expect(catcher.send(:watch_events, client, '123072296')).to be_nil
    end

    it 'rescues EOFError, logs a reconnect message, and returns the current version' do
      allow(watcher).to receive(:each).and_raise(EOFError, 'connection closed')
      expect(logger).to receive(:warn).with(/reconnecting/)
      expect(catcher.send(:watch_events, client, '99')).to eq('99')
    end

    it 'rescues OpenSSL::SSL::SSLError, logs a reconnect message, and returns the current version' do
      allow(watcher).to receive(:each).and_raise(OpenSSL::SSL::SSLError, 'unexpected eof while reading')
      expect(logger).to receive(:warn).with(/reconnecting/)
      expect(catcher.send(:watch_events, client, '99')).to eq('99')
    end
  end

  describe '#run!' do
    let(:client) { double('Kubeclient::Client') }

    before do
      allow(Kubeclient::Client).to receive(:new).and_return(client)
      allow(client).to receive(:discover)
      allow(client).to receive(:get_events).and_return(double('EventList', :resourceVersion => 'v1'))
      allow(catcher).to receive(:notify_started)
      allow(catcher).to receive(:notify_stopping)
    end

    it 'calls notify_started before the first watch loop' do
      expect(catcher).to receive(:notify_started).ordered
      expect(client).to receive(:discover).ordered
      allow(catcher).to receive(:watch_events).and_raise(Interrupt)

      catcher.run!
    end

    it 'calls watch_events in a loop until interrupted' do
      call_count = 0
      allow(catcher).to receive(:watch_events) do
        call_count += 1
        raise Interrupt if call_count >= 3

        'v1'
      end

      catcher.run!
      expect(call_count).to eq(3)
    end

    it 'reconnects after an EOFError by re-entering the watch loop' do
      # First watch_events call raises EOFError (handled internally and returns version),
      # second call raises Interrupt to stop the loop.
      allow(catcher).to receive(:watch_events).and_return('v1', 'v1').and_raise(Interrupt)
      expect { catcher.run! }.not_to raise_error
    end

    it 'calls notify_stopping in the ensure block even when interrupted' do
      allow(catcher).to receive(:watch_events).and_raise(Interrupt)
      expect(catcher).to receive(:notify_stopping)
      catcher.run!
    end

    it 'passes the version returned by watch_events into the next iteration' do
      versions_received = []
      allow(catcher).to receive(:watch_events) do |_client, ver|
        versions_received << ver
        raise Interrupt if versions_received.length >= 2

        'v2'
      end

      catcher.run!
      expect(versions_received).to eq(%w[v1 v2])
    end
  end
end
