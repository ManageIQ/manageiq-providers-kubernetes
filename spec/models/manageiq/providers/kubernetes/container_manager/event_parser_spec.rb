describe ManageIQ::Providers::Kubernetes::ContainerManager::EventParser do
  describe '.event_to_hash' do
    let(:base_event_data) do
      {
        :event_type          => 'NODE_REBOOTED',
        :kind                => 'Node',
        :name                => 'node-1',
        :namespace           => nil,
        :reason              => 'Rebooted',
        :message             => 'Node rebooted',
        :uid                 => 'node-uid-abc',
        :event_uid           => 'event-uid-xyz',
        :timestamp           => '2024-01-01T00:00:00Z',
        :container_node_name => 'node-1',
      }
    end

    context 'with a Node event' do
      it 'sets :container_node_ems_ref from :uid' do
        result = described_class.event_to_hash(base_event_data, 42)

        expect(result[:container_node_ems_ref]).to eq('node-uid-abc')
        expect(result).not_to have_key(nil)
      end
    end

    context 'with a Pod event' do
      let(:pod_event_data) do
        base_event_data.merge(
          :event_type           => 'POD_SCHEDULED',
          :kind                 => 'Pod',
          :uid                  => 'pod-uid-abc',
          :container_group_name => 'my-pod',
          :container_namespace  => 'default',
        )
      end

      it 'sets :container_group_ems_ref from :uid' do
        result = described_class.event_to_hash(pod_event_data, 42)

        expect(result[:container_group_ems_ref]).to eq('pod-uid-abc')
        expect(result).not_to have_key(nil)
      end
    end

    context 'with a replicator-family event' do
      %w[ReplicationController ReplicaSet Deployment StatefulSet DaemonSet Job CronJob].each do |kind|
        it "sets :container_replicator_ems_ref for #{kind}" do
          event_data = base_event_data.merge(
            :kind                      => kind,
            :event_type                => "#{kind.upcase}_SCALINGREPLICASET",
            :uid                       => "#{kind.downcase}-uid",
            :container_replicator_name => 'my-workload',
            :container_namespace       => 'default',
          )

          result = described_class.event_to_hash(event_data, 42)

          expect(result[:container_replicator_ems_ref]).to eq("#{kind.downcase}-uid")
          expect(result).not_to have_key(nil)
        end
      end
    end

    context 'with an unknown kind' do
      let(:unknown_event_data) do
        base_event_data.merge(
          :kind       => 'Namespace',
          :event_type => 'NAMESPACE_CREATED',
          :uid        => 'ns-uid-abc',
        )
      end

      it 'does not raise' do
        expect { described_class.event_to_hash(unknown_event_data, 42) }.not_to raise_error
      end

      it 'does not insert a nil key into the hash' do
        result = described_class.event_to_hash(unknown_event_data, 42)

        expect(result).not_to have_key(nil)
      end

      it 'does not set any ems_ref key' do
        result = described_class.event_to_hash(unknown_event_data, 42)

        expect(result).not_to have_key(:container_node_ems_ref)
        expect(result).not_to have_key(:container_group_ems_ref)
        expect(result).not_to have_key(:container_replicator_ems_ref)
      end
    end
  end
end
