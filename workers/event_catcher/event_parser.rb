class EventParser
  def self.extract_event_data(event)
    involved_object = event.object.involvedObject
    return {} if involved_object.nil?

    event_data = {
      :timestamp => event.object.lastTimestamp || event.object.eventTime,
      :kind      => involved_object.kind,
      :name      => involved_object.name,
      :namespace => involved_object.namespace,
      :reason    => event.object.reason,
      :message   => event.object.message,
      :uid       => involved_object.uid,
      :event_uid => event.object.metadata.uid,
    }

    event_data[:fieldpath] = involved_object.fieldPath unless involved_object.fieldPath.nil?

    event_type_prefix = event_data[:kind].upcase
    case event_data[:kind]
    when 'Node'
      event_data[:container_node_name] = event_data[:name]
    when 'Pod'
      /^spec.containers{(?<container_name>.*)}$/ =~ event_data[:fieldpath]
      event_data[:container_name] = container_name unless container_name.nil?
      event_data[:container_group_name] = event_data[:name]
      event_data[:container_namespace] = event_data[:namespace]
    # TODO: ReplicationController is deprecated in favour of ReplicaSet/Deployment;
    when 'ReplicationController'
      event_type_prefix = 'REPLICATOR'
      event_data[:container_replicator_name] = event_data[:name]
      event_data[:container_namespace] = event_data[:namespace]
    when 'ReplicaSet', 'Deployment', 'StatefulSet', 'DaemonSet', 'Job', 'CronJob'
      event_data[:container_namespace] = event_data[:namespace]
    end

    event_data[:event_type] = "#{event_type_prefix}_#{event_data[:reason].upcase}"
    event_data
  end

  def self.event_to_hash_from_data(event, ems_id = nil)
    # TODO: ReplicationController is deprecated in favour of ReplicaSet/Deployment;
    ems_ref_key = case event[:kind]
                  when 'Node'
                    :container_node_ems_ref
                  when 'Pod'
                    :container_group_ems_ref
                  when 'ReplicationController'
                    :container_replicator_ems_ref
                  end

    event_hash = {
      :event_type                => event[:event_type],
      :source                    => 'KUBERNETES',
      :timestamp                 => event[:timestamp],
      :message                   => event[:message],
      :container_node_name       => event[:container_node_name],
      :container_group_name      => event[:container_group_name],
      :container_replicator_name => event[:container_replicator_name],
      :container_namespace       => event[:container_namespace],
      :container_name            => event[:container_name],
      :full_data                 => event,
      :ems_id                    => ems_id,
      :ems_ref                   => event[:event_uid],
    }
    event_hash[ems_ref_key] = event[:uid] if ems_ref_key
    event_hash
  end
end
