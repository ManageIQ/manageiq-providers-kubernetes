RSpec.describe ManageIQ::Providers::Kubernetes::ContainerManager::EventCatcher::Runner do
  describe '#worker_cmdline' do
    let(:runner) { described_class.allocate }

    it 'points at the correct worker binary path' do
      expect(runner.send(:worker_cmdline)).to eq(
        ManageIQ::Providers::Kubernetes::Engine.root.join("workers/manageiq/providers/kubernetes/container_manager/event_catcher/worker").to_s
      )
    end

    it 'resolves to an existing file' do
      expect(File.exist?(runner.send(:worker_cmdline))).to be(true)
    end
  end
end
