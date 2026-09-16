require 'recursive-open-struct'
require_relative '../../../workers/event_catcher/event_parser'

RSpec.describe EventParser do
  let(:fixture_dir) { File.expand_path('data', __dir__) }

  def load_event(name)
    RecursiveOpenStruct.new(YAML.unsafe_load(File.read(File.join(fixture_dir, name))), :recurse_over_arrays => true)
  end

  def parse(name, ems_id = 42)
    described_class.event_to_hash_from_data(described_class.extract_event_data(load_event(name)), ems_id)
  end

  it 'parses a node event' do
    expect(parse('node_rebooted.yml')).to include(:event_type => 'NODE_REBOOTED', :container_node_name => 'node-1', :ems_id => 42)
  end

  it 'parses a pod event' do
    expect(parse('pod_killing.yml')).to include(:event_type => 'POD_KILLING', :container_name => 'app', :container_group_ems_ref => 'pod-uid')
  end

  it 'parses a replication controller event' do
    expect(parse('replication_controller_event.yml')).to include(:event_type => 'REPLICATOR_SUCCESSFULCREATE', :container_replicator_ems_ref => 'rc-uid')
  end

  it 'falls back to eventTime when lastTimestamp is absent' do
    event = parse('pod_scheduled.yml')
    expect(event[:timestamp]).to eq('2026-09-16T11:08:00Z')
    expect(event[:event_type]).to eq('POD_SCHEDULED')
  end

  it 'returns an empty hash when involvedObject is nil' do
    raw = RecursiveOpenStruct.new(:object => {:involvedObject => nil, :metadata => {:uid => 'x'}})
    expect(described_class.extract_event_data(raw)).to eq({})
  end
end
