describe ManageIQ::Providers::Kubernetes::ContainerManager::RefresherMixin do
  let(:client)  { double("client") }
  let(:ems)     { FactoryBot.create(:ems_kubernetes) }
  let(:dummy)   { ManageIQ::Providers::Kubernetes::ContainerManager::Refresher.new([ems]) }

  context 'when an exception is thrown' do
    before { allow(client).to receive(:get_pods) { raise KubeException.new(0, 'oh-no', nil) } }

    context 'and there is no default value' do
      it 'should raise' do
        expect { dummy.fetch_entities(client, ['pods']) }.to raise_error(KubeException)
      end
    end
  end
end
