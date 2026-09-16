require 'bundler'

RSpec.describe 'event catcher worker inline gems' do
  let(:worker_path) { File.expand_path('../../../workers/event_catcher/worker', __dir__) }
  let(:lockfile) { Bundler::LockfileParser.new(Bundler.read_file(File.expand_path('../../../Gemfile.lock', __dir__))) }

  it 'uses versions compatible with Gemfile.lock' do
    source = File.read(worker_path)
    gems = source.scan(/gem ['"]([^'"]+)['"], ['"]([^'"]+)['"]/).to_h
    gems.each do |name, requirement|
      locked = lockfile.specs.find { |spec| spec.name == name }
      expect(locked).not_to be_nil
      expect(Gem::Requirement.new(requirement).satisfied_by?(locked.version)).to be(true)
    end
  end
end
