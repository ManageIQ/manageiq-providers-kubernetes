require 'bigdecimal'
require 'shellwords'

class ManageIQ::Providers::Kubernetes::Inventory::Parser::ContainerManager < ManageIQ::Providers::Kubernetes::Inventory::Parser
  include Vmdb::Logging
  include ManageIQ::Providers::Kubernetes::ContainerManager::EntitiesMapping

  def initialize(options = Config::Options.new)
    @options = options

    @data = {}
    @data_index = {}
    @tag_mapper = ContainerLabelTagMapping.mapper
    @data[:tag_mapper] = @tag_mapper
  end

  def parse
    persister_inv_to_persister(persister, nil, refresher_options)
  end

  def persister_inv_to_persister(persister, inventory, options)
    persister.add_collection_directly(@tag_mapper.tags_to_resolve_collection)

    ems_inv_populate_collections(inventory, options)

    # The following take parsed hashes from @data_index, populated during
    # parsing pods and possibly openshift images, so must be called at the end.
    get_container_images_graph
    get_container_image_registries_graph

    # Returning Persister triggers InventoryRefresh::SaveInventory code path.
    persister
  end

  def ems_inv_populate_collections(inventory, _options)
    get_additional_attributes_graph(inventory) # TODO: untested?
    get_nodes_graph(inventory)
    get_namespaces_graph(inventory)
    get_resource_quotas_graph(inventory)
    get_limit_ranges_graph(inventory)
    get_replication_controllers_graph(inventory)
    get_persistent_volume_claims_graph(inventory)
    get_persistent_volumes_graph(inventory)
    get_pods_graph(inventory)
    get_endpoints_and_services_graph(inventory)
  end

  def get_additional_attributes_graph(inv)
    collector.additional_attributes.each do |aa|
      h = parse_additional_attribute(aa)
      next if h.empty? || h[:node].nil?

      container_node = lazy_find_node(:name => h.delete(:node))
      get_custom_attributes_graph(container_node, :additional_attributes => [h])
    end
  end

  def get_nodes_graph(inv)
    collection = persister.container_nodes

    collector.nodes.each do |data|
      h = parse_node(data)

      h.except!(:namespace)

      labels = h.delete(:labels)
      tags = h.delete(:tags)
      children = h.extract!(:container_conditions, :computer_system)

      container_node = collection.build(h)

      get_container_conditions_graph(container_node, children[:container_conditions])
      get_node_computer_systems_graph(container_node, children[:computer_system])
      get_custom_attributes_graph(container_node, :labels => labels)
      get_taggings_graph(container_node, tags)
    end
  end

  def get_node_computer_systems_graph(parent, hash)
    return if hash.nil?

    hash[:managed_entity] = parent
    children = hash.extract!(:hardware, :operating_system)

    computer_system = persister.computer_systems.build(hash)

    get_node_computer_system_hardware_graph(computer_system, children[:hardware])
    get_node_computer_system_operating_system_graph(computer_system, children[:operating_system])
  end

  def get_node_computer_system_hardware_graph(parent, hash)
    return if hash.nil?
    hash[:computer_system] = parent
    persister.computer_system_hardwares.build(hash)
  end

  def get_node_computer_system_operating_system_graph(parent, hash)
    return if hash.nil?
    hash[:computer_system] = parent
    persister.computer_system_operating_systems.build(hash)
  end

  def get_namespaces_graph(inv)
    collection = persister.container_projects

    collector.namespaces.each do |ns|
      h = parse_namespace(ns)

      custom_attrs = h.extract!(:labels)
      tags = h.delete(:tags)

      container_project = collection.build(h)

      get_custom_attributes_graph(container_project, custom_attrs) # TODO: untested
      get_taggings_graph(container_project, tags)
    end
  end

  def get_resource_quotas_graph(inv)
    collection = persister.container_quotas

    collector.resource_quotas.each do |quota|
      h = parse_resource_quota(quota)

      h[:container_project] = lazy_find_project(:name => h[:namespace])

      scopes = h.delete(:container_quota_scopes)
      items = h.delete(:container_quota_items)
      container_quota = collection.build(h)

      get_container_quota_scopes_graphs(container_quota, scopes)
      get_container_quota_items_graph(container_quota, items)
    end
  end

  def get_container_quota_scopes_graphs(parent, hashes)
    hashes.each do |hash|
      hash[:container_quota] = parent
      persister.container_quota_scopes.build(hash)
    end
  end

  def get_container_quota_items_graph(parent, hashes)
    hashes.each do |hash|
      hash[:container_quota] = parent
      persister.container_quota_items.build(hash)
    end
  end

  def get_limit_ranges_graph(inv)
    collection = persister.container_limits

    collector.limit_ranges.each do |data|
      h = parse_range(data)

      h[:container_project] = lazy_find_project(:name => h[:namespace])
      items = h.delete(:container_limit_items)

      limit = collection.build(h)

      get_limit_range_items_graph(limit, items)
    end
  end

  def get_limit_range_items_graph(parent, hashes)
    collection = persister.container_limit_items
    hashes.each do |hash|
      hash[:container_limit] = parent
      collection.build(hash)
    end
  end

  def get_replication_controllers_graph(inv)
    collection = persister.container_replicators

    collector.replication_controllers.each do |rc|
      h = parse_replication_controllers(rc)

      h[:container_project] = lazy_find_project(:name => h[:namespace])

      custom_attrs = h.extract!(:labels, :selector_parts)
      tags = h.delete(:tags)

      container_replicator = collection.build(h)
      get_custom_attributes_graph(container_replicator,
                                  :labels    => custom_attrs[:labels],
                                  # The actual section is "selectors"
                                  :selectors => custom_attrs[:selector_parts])
      get_taggings_graph(container_replicator, tags)
    end
  end

  def get_persistent_volume_claims_graph(inv)
    collection = persister.persistent_volume_claims

    collector.persistent_volume_claims.each do |pvc|
      h = parse_persistent_volume_claim(pvc)
      h[:container_project] = lazy_find_project(:name => h[:namespace])

      collection.build(h)
    end
  end

  def get_persistent_volumes_graph(inv)
    collection = persister.persistent_volumes

    collector.persistent_volumes.each do |pv|
      h = parse_persistent_volume(pv)

      h.except!(:namespace) # TODO: project untested?

      pvc_ref = h.delete(:persistent_volume_claim_ref)
      h[:persistent_volume_claim] = lazy_find_persistent_volume_claim(pvc_ref)
      collection.build(h)
    end
  end

  def get_pods_graph(_inv)
    collection = persister.container_groups

    collector.pods.each do |pod|
      h = parse_pod(pod)

      h[:container_project] = lazy_find_project(:name => h[:namespace])
      h[:container_node] = lazy_find_node(:name => h.delete(:container_node_name))
      h[:container_replicator] = lazy_find_replicator(h.delete(:container_replicator_ref))
      h[:container_build_pod] = lazy_find_build_pod(:namespace => h[:namespace],
                                                    :name      => h.delete(:build_pod_name))

      custom_attrs = h.extract!(:labels, :node_selector_parts)
      tags = h.delete(:tags)
      children = h.extract!(:containers, :container_conditions, :container_volumes)

      container_group = collection.build(h)

      get_containers_graph(container_group, children[:containers])
      get_container_conditions_graph(container_group, children[:container_conditions])
      get_container_volumes_graph(container_group, children[:container_volumes])
      get_custom_attributes_graph(container_group,
                                  :labels         => custom_attrs[:labels],
                                  # The actual section is "node_selectors"
                                  :node_selectors => custom_attrs[:node_selector_parts])
      get_taggings_graph(container_group, tags)
    end
  end

  # polymorphic, relation disambiguates parent
  def get_container_conditions_graph(parent, hashes)
    model_name = parent.inventory_collection.model_class.base_class.name
    key = [:container_conditions_for, model_name]
    collection = persister.collections[key]
    raise("can't save: missing inventory collections [#{key}]") if collection.nil?

    hashes.to_a.each do |h|
      h = h.merge(:container_entity => parent)
      collection.build(h)
    end
  end

  def get_container_volumes_graph(parent, hashes)
    collection = persister.container_volumes
    hashes.to_a.each do |h|
      h = h.merge(:parent => parent)
      pvc_ref = h.delete(:persistent_volume_claim_ref)
      h[:persistent_volume_claim] = lazy_find_persistent_volume_claim(pvc_ref)
      collection.build(h)
    end
  end

  def get_container_port_configs_graph(parent, hashes)
    collection = persister.container_port_configs
    hashes.each do |h|
      h[:container] = parent
      collection.build(h)
    end
  end

  def get_container_env_vars_graph(parent, hashes)
    collection = persister.container_env_vars
    hashes.each do |h|
      h[:container] = parent
      collection.build(h)
    end
  end

  def get_container_security_context_graph(parent, h)
    collection = persister.security_contexts
    h[:resource] = parent
    collection.build(h)
  end

  def get_containers_graph(parent, hashes)
    collection = persister.containers

    hashes.each do |h|
      h[:container_group] = parent
      h[:container_image] = lazy_find_image(h[:container_image])
      children = h.extract!(:container_port_configs, :container_env_vars, :security_context)

      container = collection.build(h)

      get_container_port_configs_graph(container, children[:container_port_configs])
      get_container_env_vars_graph(container, children[:container_env_vars])
      get_container_security_context_graph(container, children[:security_context]) if children[:security_context]
    end
  end

  # TODO: how would this work with partial refresh?
  # TODO: can I write get_endpoints() that directly refreshes ContainerGroupsContainerServices join table?
  def get_endpoints_and_services_graph(inv)
    cgs_by_namespace_and_name = {}

    # We don't save endpoints themselves, only parse for cross-linking services<->pods
    collector.endpoints.each do |endpoint|
      ep = parse_endpoint(endpoint)

      container_groups = []
      ep.delete(:container_groups_refs).each do |ref|
        next if ref.nil?
        cg = lazy_find_container_group(:namespace => ref[:namespace], :name => ref[:name])
        container_groups << cg unless cg.nil?
      end
      cgs_by_namespace_and_name.store_path(ep[:namespace], ep[:name], container_groups)
    end

    collection = persister.container_services

    collector.services.each do |service|
      h = parse_service(service)

      h[:container_project] = lazy_find_project(:name => h[:namespace]) # TODO: untested?

      # TODO: with multiple ports, how can I match any of them to known registries,
      # like https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/57 ?
      if h[:container_service_port_configs].any?
        registry_port = h[:container_service_port_configs].last[:port]
        h[:container_image_registry] = lazy_find_image_registry(
          :host => h[:portal_ip], :port => registry_port
        )
      end

      custom_attrs = h.extract!(:labels, :selector_parts)
      tags = h.delete(:tags)
      children = h.extract!(:container_service_port_configs)

      h[:container_groups] = cgs_by_namespace_and_name.fetch_path(h[:namespace], h[:name]) || []

      container_service = collection.build(h)

      get_container_service_port_configs_graph(container_service, children[:container_service_port_configs])
      get_custom_attributes_graph(container_service,
                                  :labels    => custom_attrs[:labels],
                                  # The actual section is "selectors"
                                  :selectors => custom_attrs[:selector_parts])
      get_taggings_graph(container_service, tags)
    end
  end

  def get_container_service_port_configs_graph(container_service, hashes)
    hashes.to_a.each do |h|
      h = h.merge(:container_service => container_service)
      persister.container_service_port_configs.build(h)
    end
  end

  # TODO: images & registries still rely on @data_index
  def get_container_image_registries_graph
    collection = persister.container_image_registries
    # Resulting from previously parsed images
    registries = @data_index.fetch_path(:container_image_registry, :by_host_and_port) || []
    registries.each do |_host_port, ir|
      collection.build(ir)
    end
  end

  def get_container_images_graph
    collection = persister.container_images
    # Resulting from previously parsed images
    images = @data_index.fetch_path(:container_image, :by_digest) || []
    images.each do |_digest, im|
      im = im.merge(:container_image_registry => lazy_find_image_registry(im[:container_image_registry]))
      custom_attrs = im.extract!(:labels, :docker_labels)
      container_image = collection.build(im)

      get_custom_attributes_graph(container_image, custom_attrs)
    end
  end

  def get_custom_attributes_graph(parent, hashes_by_section)
    model_name = parent.inventory_collection.model_class.base_class.name
    hashes_by_section.each do |section, hashes|
      key = [:custom_attributes_for, model_name, section.to_s]
      collection = persister.collections[key]
      raise("can't save: missing inventory collections [#{key}]") if collection.nil?
      hashes.to_a.each do |h|
        h = h.merge(:resource => parent)
        if h[:section].to_s != section.to_s
          raise("unexpected hash with section #{h[:section]} under #{section}")
        end
        collection.build(h)
      end
    end
  end

  # Conveniently, the tags map_labels emits are already in InventoryObject<Tag> form
  def get_taggings_graph(parent, tags_inventory_objects)
    model_name = parent.inventory_collection.model_class.base_class.name
    key = [:taggings_for, model_name]
    collection = persister.collections[key]
    raise("can't save: missing inventory collections [#{key}]") if collection.nil?
    tags_inventory_objects.each do |tag|
      collection.build(:taggable => parent, :tag => tag)
    end
  end

  ## Helpers for @data / @data_index

  def process_collection(collection, key, &block)
    @data[key] ||= []
    collection.each { |item| process_collection_item(item, key, &block) }
  end

  def process_collection_item(item, key)
    @data[key] ||= []

    new_result = yield(item)

    @data[key] << new_result
    new_result
  end

  def find_or_store_data(data_index_path, data_key, new_result)
    @data_index.fetch_path(*data_index_path) ||
      begin
        @data_index.store_path(*data_index_path, new_result)
        process_collection_item(new_result, data_key) { |x| x }
        new_result
      end
  end

  ## Shared parsing methods

  def map_labels(model_name, labels)
    @tag_mapper.map_labels(model_name, labels)
  end

  def find_host_by_provider_id(provider_id)
    scheme, instance_uri = provider_id.split("://", 2)
    prov, name_field = scheme_to_provider_mapping[scheme]
    instance_id = instance_uri.split('/').last

    prov::Vm.find_by(name_field => instance_id) if !prov.nil? && !instance_id.blank?
  end

  def scheme_to_provider_mapping
    @scheme_to_provider_mapping ||= begin
      {
        'gce'       => ['ManageIQ::Providers::Google::CloudManager'.safe_constantize, :name],
        'aws'       => ['ManageIQ::Providers::Amazon::CloudManager'.safe_constantize, :uid_ems],
        'openstack' => ['ManageIQ::Providers::Openstack::CloudManager'.safe_constantize, :uid_ems]
      }.reject { |_key, (provider, _name)| provider.nil? }
    end
  end

  def find_host_by_bios_uuid(new_result)
    identity_system = new_result[:identity_system].try(:downcase)
    Vm.find_by(:uid_ems => identity_system,
               :type    => uuid_provider_types) if identity_system
  end

  def uuid_provider_types
    @uuid_provider_types ||= begin
      ['ManageIQ::Providers::Redhat::InfraManager::Vm',
       'ManageIQ::Providers::Openstack::CloudManager::Vm',
       'ManageIQ::Providers::Vmware::InfraManager::Vm'].map(&:safe_constantize).compact.map(&:name)
    end
  end

  def cross_link_node(new_result)
    # Establish a relationship between this node and the vm it is on (if it is in the system)
    host_instance = nil
    unless new_result[:identity_infra].blank?
      host_instance = find_host_by_provider_id(new_result[:identity_infra])
    end
    unless host_instance
      host_instance = find_host_by_bios_uuid(new_result)
    end

    new_result[:lives_on_id] = host_instance.try(:id)
    new_result[:lives_on_type] = host_instance.try(:type)
  end

  def parse_additional_attribute(attribute)
    # Assuming keys are in format "node/<hostname.example.com/key"
    if attribute[0] && attribute[0].split("/").count == 3
      { attribute[0].split("/").first.to_sym => attribute[0].split("/").second,
        :name                                => attribute[0].split("/").last,
        :value                               => attribute[1],
        :section                             => "additional_attributes"}
    else
      {}
    end
  end

  def parse_node(node)
    new_result = parse_base_item(node)

    labels = parse_labels(node)
    new_result.merge!(
      :type           => 'ManageIQ::Providers::Kubernetes::ContainerManager::ContainerNode',
      :identity_infra => node.spec.providerID,
      :labels         => labels,
      :tags           => map_labels('ContainerNode', labels),
      :lives_on_id    => nil,
      :lives_on_type  => nil
    )

    node_info = node.status.try(:nodeInfo)
    if node_info
      new_result.merge!(
        :identity_machine           => node_info.machineID,
        :identity_system            => node_info.systemUUID,
        :container_runtime_version  => node_info.containerRuntimeVersion,
        :kubernetes_proxy_version   => node_info.kubeProxyVersion,
        :kubernetes_kubelet_version => node_info.kubeletVersion
      )
    end

    node_memory = node.status.try(:capacity).try(:memory)
    node_memory = parse_capacity_field("Node-Memory", node_memory)
    node_memory &&= node_memory / 1.megabyte

    new_result[:computer_system] = {
      :hardware         => {
        :cpu_total_cores => node.status.try(:capacity).try(:cpu),
        :memory_mb       => node_memory
      },
      :operating_system => {
        :distribution   => node_info.try(:osImage),
        :kernel_version => node_info.try(:kernelVersion)
      }
    }

    max_container_groups = node.status.try(:capacity).try(:pods)
    new_result[:max_container_groups] = parse_capacity_field("Pods", max_container_groups)

    new_result[:container_conditions] = parse_conditions(node)
    cross_link_node(new_result)

    new_result
  end

  def parse_service(service)
    new_result = parse_base_item(service)

    if new_result[:ems_ref].nil? # Typically this happens for kubernetes services
      new_result[:ems_ref] = "#{new_result[:namespace]}_#{new_result[:name]}"
    end

    labels = parse_labels(service)
    new_result.merge!(
      # TODO: We might want to change portal_ip to clusterIP
      :portal_ip        => service.spec.clusterIP,
      :session_affinity => service.spec.sessionAffinity,
      :service_type     => service.spec.type,
      :labels           => labels,
      :tags             => map_labels('ContainerService', labels),
      :selector_parts   => parse_selector_parts(service),
    )

    ports = service.spec.ports
    new_result[:container_service_port_configs] = Array(ports).collect do |port_entry|
      parse_service_port_config(port_entry, new_result[:ems_ref])
    end

    new_result
  end

  def parse_pod(pod)
    # pod in kubernetes is container group in manageiq
    new_result = parse_base_item(pod)

    new_result.merge!(
      :type                => 'ManageIQ::Providers::Kubernetes::ContainerManager::ContainerGroup',
      :restart_policy      => pod.spec.restartPolicy,
      :dns_policy          => pod.spec.dnsPolicy,
      :ipaddress           => pod.status.podIP,
      :phase               => pod.status.phase,
      :message             => pod.status.message,
      :reason              => pod.status.reason,
      :container_node_name => pod.spec.nodeName,
      :containers          => [],
      :build_pod_name      => pod.metadata.try(:annotations).try("openshift.io/build.name".to_sym)
    )

    # TODO, map volumes
    # TODO, podIP
    containers_index = {}
    containers = pod.spec.containers
    containers.each do |container_spec|
      containers_index[container_spec.name] = parse_container_spec(container_spec, pod.metadata.uid)
      new_result[:containers] << containers_index[container_spec.name]
    end

    unless pod.status.nil? || pod.status.containerStatuses.nil?
      pod.status.containerStatuses.each do |cn|
        container_status = parse_container_status(cn, pod.metadata.uid)
        if container_status.nil?
          _log.error("Invalid container status: pod - [#{pod.metadata.uid}] container - [#{cn}] [#{containers_index[cn.name]}]")
          next
        end

        containers_index[cn.name] ||= {}
        containers_index[cn.name].merge!(container_status)
      end
    end

    new_result[:container_replicator_ref] = nil
    # NOTE: what we are trying to access here is the attribute:
    #   pod.metadata.annotations.kubernetes.io/created-by
    # but 'annotations' may be nil. The weird attribute name is
    # generated by the JSON unmarshalling.
    createdby_txt = pod.metadata.annotations.try("kubernetes.io/created-by")
    unless createdby_txt.nil?
      # NOTE: the annotation content is JSON, so it needs to be parsed
      createdby = JSON.parse(createdby_txt)
      if createdby.kind_of?(Hash) && !createdby['reference'].nil?
        new_result[:container_replicator_ref] = {
          :namespace => createdby['reference']['namespace'],
          :name      => createdby['reference']['name']
        }
      end
    end

    new_result[:container_conditions] = parse_conditions(pod)

    new_result[:labels] = parse_labels(pod)
    new_result[:tags] = map_labels('ContainerGroup', new_result[:labels])
    new_result[:node_selector_parts] = parse_node_selector_parts(pod)
    new_result[:container_volumes] = parse_volumes(pod)
    new_result
  end

  def parse_endpoint(entity)
    new_result = parse_base_item(entity)
    new_result[:container_groups_refs] = []

    (entity.subsets || []).each do |subset|
      (subset.addresses || []).each do |address|
        next if address.targetRef.nil? || address.targetRef.kind != 'Pod'
        new_result[:container_groups_refs] << {
          :namespace => address.targetRef.namespace,
          :name      => address.targetRef.name,
        }
      end
    end

    new_result
  end

  def parse_namespace(namespace)
    new_result = parse_base_item(namespace).except(:namespace)
    new_result[:labels] = parse_labels(namespace)
    new_result[:tags] = map_labels('ContainerProject', new_result[:labels])
    new_result
  end

  def parse_persistent_volume(persistent_volume)
    new_result = parse_base_item(persistent_volume)
    new_result.merge!(parse_volume_source(persistent_volume.spec))
    new_result.merge!(
      :type                        => 'PersistentVolume',
      :capacity                    => parse_resource_list(persistent_volume.spec.capacity.to_h),
      :access_modes                => persistent_volume.spec.accessModes.join(','),
      :reclaim_policy              => persistent_volume.spec.persistentVolumeReclaimPolicy,
      :status_phase                => persistent_volume.status.phase,
      :status_message              => persistent_volume.status.message,
      :status_reason               => persistent_volume.status.reason,
      :persistent_volume_claim_ref => nil,
    )

    unless persistent_volume.spec.claimRef.nil?
      new_result[:persistent_volume_claim_ref] = {
        :namespace => persistent_volume.spec.claimRef.namespace,
        :name      => persistent_volume.spec.claimRef.name,
      }
    end

    new_result
  end

  def parse_resource_list(hash)
    hash.each_with_object({}) do |(key, val), result|
      res = parse_capacity_field(key, val)
      result[key] = res if res
    end
  end

  def parse_capacity_field(key, val)
    return nil unless val
    begin
      parse_quantity(val)
    rescue ArgumentError
      _log.warn("Capacity attribute - #{key} was in bad format - #{val}")
      nil
    end
  end

  def parse_persistent_volume_claim(claim)
    new_result = parse_base_item(claim)
    new_result.merge!(
      :desired_access_modes => claim.spec.accessModes,
      :requests             => parse_resource_list(claim.spec.resources.requests.to_h),
      :limits               => parse_resource_list(claim.spec.resources.limits.to_h),
      :phase                => claim.status.phase,
      :actual_access_modes  => claim.status.accessModes,
      :capacity             => parse_resource_list(claim.status.capacity.to_h),
    )

    new_result
  end

  def parse_resource_quota(resource_quota)
    new_result = parse_base_item(resource_quota)
    new_result[:container_quota_scopes] = resource_quota.spec.scopes.to_a.collect { |scope| {:scope => scope} }
    new_result[:container_quota_items] = parse_resource_quota_items(resource_quota)
    new_result
  end

  def parse_resource_quota_items(resource_quota)
    new_result_h = Hash.new do |h, k|
      h[k] = {
        :resource       => k.to_s,
        :quota_desired  => nil,
        :quota_enforced => nil,
        :quota_observed => nil
      }
    end

    resource_quota.spec.hard.to_h.each do |resource_name, quota|
      new_result_h[resource_name][:quota_desired] = parse_quantity_decimal(quota)
    end

    resource_quota.status.hard.to_h.each do |resource_name, quota|
      new_result_h[resource_name][:quota_enforced] = parse_quantity_decimal(quota)
    end

    resource_quota.status.used.to_h.each do |resource_name, quota|
      new_result_h[resource_name][:quota_observed] = parse_quantity_decimal(quota)
    end

    new_result_h.values
  end

  def parse_range(limit_range)
    new_result = parse_base_item(limit_range)
    new_result[:container_limit_items] = parse_range_items limit_range
    new_result
  end

  def parse_range_items(limit_range)
    new_result_h = create_limits_matrix

    limits = limit_range.try(:spec).try(:limits) || []
    limits.each do |item|
      item[:max].to_h.each do |resource_name, limit|
        new_result_h[item[:type].to_sym][resource_name.to_sym][:max] = limit
      end

      item[:min].to_h.each do |resource_name, limit|
        new_result_h[item[:type].to_sym][resource_name.to_sym][:min] = limit
      end

      item[:default].to_h.each do |resource_name, limit|
        new_result_h[item[:type].to_sym][resource_name.to_sym][:default] = limit
      end

      item[:defaultRequest].to_h.each do |resource_name, limit|
        new_result_h[item[:type].to_sym][resource_name.to_sym][:default_request] = limit
      end

      item[:maxLimitRequestRatio].to_h.each do |resource_name, limit|
        new_result_h[item[:type].to_sym][resource_name.to_sym][:max_limit_request_ratio] = limit
      end
    end
    new_result_h.values.collect(&:values).flatten
  end

  def create_limits_matrix
    # example: h[:pod][:cpu][:max] = 8
    Hash.new do |h, item_type|
      h[item_type] = Hash.new do |j, resource|
        j[resource] = {
          :item_type               => item_type.to_s,
          :resource                => resource.to_s,
          :max                     => nil,
          :min                     => nil,
          :default                 => nil,
          :default_request         => nil,
          :max_limit_request_ratio => nil
        }
      end
    end
  end

  def parse_replication_controllers(container_replicator)
    new_result = parse_base_item(container_replicator)

    labels = parse_labels(container_replicator)
    # TODO: parse template
    new_result.merge!(
      :replicas         => container_replicator.spec.replicas,
      :current_replicas => container_replicator.status.replicas,
      :labels           => labels,
      :tags             => map_labels('ContainerReplicator', labels),
      :selector_parts   => parse_selector_parts(container_replicator)
    )
    new_result
  end

  def parse_labels(entity)
    parse_identifying_attributes(entity.metadata.labels, 'labels')
  end

  def parse_selector_parts(entity)
    parse_identifying_attributes(entity.spec.selector, 'selectors')
  end

  def parse_node_selector_parts(entity)
    parse_identifying_attributes(entity.spec.nodeSelector, 'node_selectors')
  end

  def parse_identifying_attributes(attributes, section, source = "kubernetes")
    result = []
    return result if attributes.nil?
    attributes.to_h.each do |key, value|
      custom_attr = {
        :section => section,
        :name    => key.to_s,
        :value   => value,
        :source  => source
      }
      result << custom_attr
    end
    result
  end

  def parse_conditions(entity)
    conditions = entity.status.try(:conditions)
    conditions.to_a.collect do |condition|
      {
        :name                 => condition.type,
        :status               => condition.status,
        :last_heartbeat_time  => condition.lastHeartbeatTime,
        :last_transition_time => condition.lastTransitionTime,
        :reason               => condition.reason,
        :message              => condition.message
      }
    end
  end

  def parse_container_spec(container_spec, pod_id)
    new_result = {
      :type                 => 'ManageIQ::Providers::Kubernetes::ContainerManager::Container',
      :ems_ref              => "#{pod_id}_#{container_spec.name}_#{container_spec.image}",
      :name                 => container_spec.name,
      :image                => container_spec.image,
      :image_pull_policy    => container_spec.imagePullPolicy,
      :command              => container_spec.command ? Shellwords.join(container_spec.command) : nil,
      :memory               => container_spec.memory,
      # https://github.com/GoogleCloudPlatform/kubernetes/blob/0b801a91b15591e2e6e156cf714bfb866807bf30/pkg/api/v1beta3/types.go#L815
      :cpu_cores            => container_spec.cpu.to_f / 1000,
      :capabilities_add     => container_spec.securityContext.try(:capabilities).try(:add).to_a.join(','),
      :capabilities_drop    => container_spec.securityContext.try(:capabilities).try(:drop).to_a.join(','),
      :privileged           => container_spec.securityContext.try(:privileged),
      :run_as_user          => container_spec.securityContext.try(:runAsUser),
      :run_as_non_root      => container_spec.securityContext.try(:runAsNonRoot),
      :security_context     => parse_security_context(container_spec.securityContext),
      :limit_cpu_cores      => parse_quantity(container_spec.try(:resources).try(:limits).try(:cpu)),
      :limit_memory_bytes   => parse_quantity(container_spec.try(:resources).try(:limits).try(:memory)),
      :request_cpu_cores    => parse_quantity(container_spec.try(:resources).try(:requests).try(:cpu)),
      :request_memory_bytes => parse_quantity(container_spec.try(:resources).try(:requests).try(:memory))
    }
    ports = container_spec.ports

    new_result[:container_port_configs] = Array(ports).collect do |port_entry|
      parse_container_port_config(port_entry, pod_id, container_spec.name)
    end
    env = container_spec.env
    new_result[:container_env_vars] = Array(env).collect do |env_var|
      parse_container_env_var(env_var)
    end

    new_result
  end

  # parse a string with a suffix into a int/float
  def parse_quantity(value)
    return nil if value.nil?

    begin
      value.iec_60027_2_to_i
    rescue
      value.decimal_si_to_f
    end
  end

  # parse a string with a suffix into a BigDecimal
  def parse_quantity_decimal(value)
    return nil if value.nil?

    begin
      BigDecimal(value.iec_60027_2_to_i)
    rescue
      value.decimal_si_to_big_decimal
    end
  end

  def parse_container_status(container, pod_id)
    container_image = parse_container_image(container.image, container.imageID)
    return if container_image.nil?

    h = {
      :restart_count   => container.restartCount,
      :backing_ref     => container.containerID,
      :container_image => container_image
    }
    state_attributes = parse_container_state container.lastState
    state_attributes.each { |key, val| h[key.to_s.prepend('last_').to_sym] = val } if state_attributes
    h.merge!(parse_container_state(container.state))
  end

  def parse_container_state(state_hash)
    return {} if state_hash.to_h.empty?
    res = {}
    # state_hash key is the state and value are attributes e.g 'running': {...}
    (state, state_info), = state_hash.to_h.to_a
    res[:state] = state
    %w(reason started_at finished_at exit_code signal message).each do |attr|
      res[attr.to_sym] = state_info[attr.camelize(:lower)]
    end
    res
  end

  # may return nil if store_new_images = false
  def parse_container_image(image, imageID, store_new_images: true)
    container_image, container_image_registry = parse_image_name(image, imageID)
    return if container_image.nil?

    stored_container_image_registry = find_or_store_container_image_registry(container_image_registry)

    if store_new_images
      stored_container_image = find_or_store_container_image(container_image)
    else
      stored_container_image = @data_index.fetch_path(index_path_for_container_image(container_image))
      return if stored_container_image.nil?
    end

    # TODO: should this linking be done for previously stored images too?
    stored_container_image[:container_image_registry] = stored_container_image_registry
    stored_container_image
  end

  def parse_container_port_config(port_config, pod_id, container_name)
    {
      :ems_ref   => "#{pod_id}_#{container_name}_#{port_config.containerPort}_#{port_config.hostPort}_#{port_config.protocol}",
      :port      => port_config.containerPort,
      :host_port => port_config.hostPort,
      :protocol  => port_config.protocol,
      :name      => port_config.name
    }
  end

  def parse_service_port_config(port_config, service_id)
    {
      :ems_ref     => "#{service_id}_#{port_config.port}_#{port_config.targetPort}",
      :name        => port_config.name,
      :protocol    => port_config.protocol,
      :port        => port_config.port,
      :target_port => (port_config.targetPort unless port_config.targetPort == 0),
      :node_port   => (port_config.nodePort unless port_config.nodePort == 0)
    }
  end

  def parse_container_env_var(env_var)
    {
      :name       => env_var.name,
      :value      => env_var.value,
      :field_path => env_var.valueFrom.try(:fieldRef).try(:fieldPath)
    }
  end

  private

  def parse_base_item(item)
    {
      :ems_ref          => item.metadata.uid,
      :name             => item.metadata.name,
      :namespace        => item.metadata.namespace,
      :ems_created_on   => item.metadata.creationTimestamp,
      :resource_version => item.metadata.resourceVersion
    }
  end

  def parse_image_name(image, image_ref)
    # parsing using same logic as in docker
    # https://github.com/docker/docker/blob/348f6529b71502b561aa493e250fd5be248da0d5/reference/reference.go#L174
    docker_pullable_re = %r{
      \A
        (?<protocol>#{ContainerImage::DOCKER_PULLABLE_PREFIX})?
        (?:(?:
          (?<host>([^\.:/]+\.)+[^\.:/]+)|
          (?:(?<host2>[^:/]+)(?::(?<port>\d+)))|
          (?<localhost>localhost)
        )/)?
        (?<name>(?:[^:/@]+/)*[^/:@]+)
        (?::(?<tag>[^:/@]+))?
        (?:\@(?<digest>.+))?
      \z
    }x
    docker_daemon_re = %r{
      \A
        (?<protocol>#{ContainerImage::DOCKER_IMAGE_PREFIX})?
          (?<digest>(sha256:)?.+)?
      \z
    }x

    image_parts = docker_pullable_re.match(image)
    if image_parts.nil?
      _log.error("Invalid image #{image}")
      return
    end

    image_ref_parts = docker_pullable_re.match(image_ref) || docker_daemon_re.match(image_ref)
    if image_ref_parts.nil?
      _log.error("Invalid image_ref #{image_ref}")
      return
    end

    if image_ref.start_with?(ContainerImage::DOCKER_PULLABLE_PREFIX)
      hostname = image_ref_parts[:host] || image_ref_parts[:host2]
      port = image_ref_parts[:port]
      digest = image_ref_parts[:digest]
    else
      hostname = image_parts[:host] || image_parts[:host2] || image_parts[:localhost]
      port = image_parts[:port]
      digest = image_parts[:digest] || image_ref_parts.try(:[], :digest)
      registry = ((port.present? ? "#{hostname}:#{port}/" : "#{hostname}/") if hostname.present?)
      image_ref = "%{prefix}%{registry}%{name}%{digest}" % {
        :prefix   => ContainerImage::DOCKER_IMAGE_PREFIX,
        :registry => registry,
        :name     => image_parts[:name],
        :digest   => ("@#{digest}" if !digest.blank?),
      }
    end

    [
      {
        :name      => image_parts[:name],
        :tag       => image_parts[:tag],
        :digest    => digest,
        :image_ref => image_ref,
      },
      hostname && {
        :name => hostname,
        :host => hostname,
        :port => image_parts[:port],
      },
    ]
  end

  def parse_security_context(security_context)
    return if security_context.nil?
    {
      :se_linux_level => security_context.seLinuxOptions.try(:level),
      :se_linux_user  => security_context.seLinuxOptions.try(:user),
      :se_linux_role  => security_context.seLinuxOptions.try(:role),
      :se_linux_type  => security_context.seLinuxOptions.try(:type)
    }
  end

  def parse_volumes(pod)
    pod.spec.volumes.to_a.collect do |volume|
      new_result = {
        :type => 'ContainerVolume',
        :name => volume.name,
      }.merge!(parse_volume_source(volume))
      if volume.persistentVolumeClaim.try(:claimName)
        new_result[:persistent_volume_claim_ref] = {
          :namespace => pod.metadata.namespace,
          :name      => volume.persistentVolumeClaim.claimName,
        }
      end
      new_result
    end
  end

  def parse_volume_source(volume)
    {
      :empty_dir_medium_type   => volume.emptyDir.try(:medium),
      :gce_pd_name             => volume.gcePersistentDisk.try(:pdName),
      :git_repository          => volume.gitRepo.try(:repository),
      :git_revision            => volume.gitRepo.try(:revision),
      :nfs_server              => volume.nfs.try(:server),
      :iscsi_target_portal     => volume.iscsi.try(:targetPortal),
      :iscsi_iqn               => volume.iscsi.try(:iqn),
      :iscsi_lun               => volume.iscsi.try(:lun),
      :glusterfs_endpoint_name => volume.glusterfs.try(:endpointsName),
      :claim_name              => volume.persistentVolumeClaim.try(:claimName),
      :rbd_ceph_monitors       => volume.rbd.try(:cephMonitors).to_a.join(','),
      :rbd_image               => volume.rbd.try(:rbdImage),
      :rbd_pool                => volume.rbd.try(:rbdPool),
      :rbd_rados_user          => volume.rbd.try(:radosUser),
      :rbd_keyring             => volume.rbd.try(:keyring),
      :common_path             => [volume.hostPath.try(:path),
                                   volume.nfs.try(:path),
                                   volume.glusterfs.try(:path)].compact.first,
      :common_fs_type          => [volume.gcePersistentDisk.try(:fsType),
                                   volume.awsElasticBlockStore.try(:fsType),
                                   volume.iscsi.try(:fsType),
                                   volume.rbd.try(:fsType),
                                   volume.cinder.try(:fsType)].compact.first,
      :common_read_only        => [volume.gcePersistentDisk.try(:readOnly),
                                   volume.awsElasticBlockStore.try(:readOnly),
                                   volume.nfs.try(:readOnly),
                                   volume.iscsi.try(:readOnly),
                                   volume.glusterfs.try(:readOnly),
                                   volume.persistentVolumeClaim.try(:readOnly),
                                   volume.rbd.try(:readOnly),
                                   volume.cinder.try(:readOnly)].compact.first,
      :common_secret           => [volume.secret.try(:secretName),
                                   volume.rbd.try(:secretRef).try(:name)].compact.first,
      :common_volume_id        => [volume.awsElasticBlockStore.try(:volumeId),
                                   volume.cinder.try(:volumeId)].compact.first,
      :common_partition        => [volume.gcePersistentDisk.try(:partition),
                                   volume.awsElasticBlockStore.try(:partition)].compact.first
    }
  end

  def path_for_entity(entity)
    resource_by_entity(entity).tableize.to_sym
  end

  def find_or_store_container_image_registry(container_image_registry)
    return nil if container_image_registry.nil?

    host_port = "#{container_image_registry[:host]}:#{container_image_registry[:port]}"
    path = [:container_image_registry, :by_host_and_port, host_port]
    find_or_store_data(path, :container_image_registries, container_image_registry)
  end

  def find_or_store_container_image(container_image)
    find_or_store_data(index_path_for_container_image(container_image), :container_images, container_image)
  end

  def index_path_for_container_image(container_image)
    # If a digest exists then it is more identifiying than the image name/repo/tag
    # as one image might have many names/repos/tags.
    container_image_identity = container_image[:digest] || container_image[:image_ref]
    # TODO: "by_digest" is not precise.
    [:container_image, :by_digest, container_image_identity]
  end

  def lazy_find_project(name:)
    return nil if name.nil?
    persister.container_projects.lazy_find(name, :ref => :by_name)
  end

  def lazy_find_node(name:)
    return nil if name.nil?
    persister.container_nodes.lazy_find(name, :ref => :by_name)
  end

  def lazy_find_replicator(hash)
    return nil if hash.nil?
    search = {:container_project => lazy_find_project(:name => hash[:namespace]), :name => hash[:name]}
    persister.container_replicators.lazy_find_by(search, :ref => :by_container_project_and_name)
  end

  def lazy_find_container_group(hash)
    return nil if hash.nil?
    search = {:container_project => lazy_find_project(:name => hash[:namespace]), :name => hash[:name]}
    persister.container_groups.lazy_find_by(search, :ref => :by_container_project_and_name)
  end

  def lazy_find_image(hash)
    return nil if hash.nil?
    hash = hash.merge(:container_image_registry => lazy_find_image_registry(hash[:container_image_registry]))
    persister.container_images.lazy_find_by(hash)
  end

  def lazy_find_image_registry(hash)
    return nil if hash.nil?
    persister.container_image_registries.lazy_find_by(hash)
  end

  def lazy_find_build_pod(hash)
    return nil if hash.nil?
    persister.container_build_pods.lazy_find_by(hash, :ref => :by_namespace_and_name)
  end

  def lazy_find_persistent_volume_claim(hash)
    return nil if hash.nil?
    search = {:container_project => lazy_find_project(:name => hash[:namespace]), :name => hash[:name]}
    persister.persistent_volume_claims.lazy_find_by(search, :ref => :by_container_project_and_name)
  end
end
