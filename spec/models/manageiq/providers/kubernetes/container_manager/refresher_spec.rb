describe ManageIQ::Providers::Kubernetes::ContainerManager::Refresher do
  include Spec::Support::EmsRefreshHelper

  let!(:openstack_vm) { FactoryBot.create(:vm_openstack, :uid_ems => '8b6c7070-9abd-41ac-a950-e4cfac665673') }
  let!(:ovirt_vm)     { FactoryBot.create(:vm_redhat,    :uid_ems => 'cad16607-fb88-4412-a993-5242030f6afa') }
  let!(:ems) do
    FactoryBot.create(
      :ems_kubernetes_with_zone,
      :hostname        => "10.35.0.169",
      :ipaddress       => "10.35.0.169",
      :port            => 6443,
      :authentications => [
        AuthToken.new(:name => "test", :auth_key => "valid-token")
      ]
    )
  end

  [
    {:saver_strategy => "default"},
    {:saver_strategy => "batch", :use_ar_object => true},
    {:saver_strategy => "batch", :use_ar_object => false}
  ].each do |saver_options|
    context "with #{saver_options}" do
      before(:each) { stub_settings_merge(:ems_refresh => {:kubernetes => {:inventory_collections => saver_options}}) }

      it ".ems_type" do
        expect(described_class.ems_type).to eq(:kubernetes)
      end

      # Smoke test the use of ContainerLabelTagMapping during refresh.
      before :each do
        mapping = FactoryBot.create(:tag_mapping_with_category, :label_name => 'name')
        @name_category = mapping.tag.classification

        @user_tag = FactoryBot.create(:classification_cost_center_with_tags).entries.first.tag
      end

      def full_refresh_test(expected_extra_tags: [])
        full_refresh

        # All ems_ref fields and other auto generated fields aren't checked because the VCR file needs update
        # every time the api changes. Until the api stabilizes, the tests on those fields are commented out.
        assert_ems
        assert_authentication
        assert_table_counts
        assert_specific_container
        assert_specific_container_group(:expected_extra_tags => expected_extra_tags)
        assert_specific_container_node
        assert_specific_container_service
        assert_specific_container_replicator(:expected_extra_tags => expected_extra_tags)
        assert_specific_container_project
        assert_specific_container_limit
        assert_specific_container_image_and_registry
        # Quotas, Volumes, PVs, and PVCs are tested in _before_deletions VCR.
      end

      it "will perform a full refresh on k8s" do
        # Run three times to verify that second & third runs with existing data do not change anything
        full_refresh_test

        # Now records exist, simulate user assigning tags by Edit Tags, to test later refreshes don't remove them.
        @replicator.reload.tags |= [@user_tag]
        @containergroup.reload.tags |= [@user_tag]

        full_refresh_test(:expected_extra_tags => [@user_tag])
        full_refresh_test(:expected_extra_tags => [@user_tag])
      end

      def assert_table_counts
        expect(ContainerGroup.count).to eq(2)
        expect(ContainerNode.count).to eq(2)
        expect(Container.count).to eq(3)
        expect(ContainerService.count).to eq(5)
        expect(ContainerPortConfig.count).to eq(2)
        expect(ContainerEnvVar.count).to eq(3)
        expect(ContainerReplicator.count).to eq(2)
        expect(ContainerProject.count).to eq(1)
        expect(ContainerQuota.count).to eq(2)
        expect(ContainerLimit.count).to eq(3)
        expect(ContainerImage.count).to eq(3)
        expect(ContainerImageRegistry.count).to eq(1)
        expect(PersistentVolume.count).to eq(1)
      end

      def assert_ems
        expect(ems).to have_attributes(
          :port => 6443,
          :type => "ManageIQ::Providers::Kubernetes::ContainerManager"
        )
      end

      def assert_authentication
        expect(ems.authentication_tokens.count).to eq(1)
        token = ems.authentication_tokens.last
        expect(token).to have_attributes(
          :auth_key => 'valid-token'
        )
      end

      def assert_specific_container
        @container = Container.find_by(:name => "heapster")
        expect(@container).to have_attributes(
          # :ems_ref     => "a7566742-e73f-11e4-b613-001a4a5f4a02_heapster_kubernetes/heapster:v0.9",
          :name          => "heapster",
          :restart_count => 2,
          :state         => "running",
          :last_state    => "terminated"
          # :backing_ref => "docker://87cd51044d7175c246fa1fa7699253fc2aecb769021837a966fa71e9dcb54d71"
        )

        [
          @container.started_at,
          @container.finished_at,
          @container.last_started_at,
          @container.last_finished_at,
        ].each do |date_|
          expect(date_.kind_of?(ActiveSupport::TimeWithZone) || date_.kind_of?(NilClass)).to be_truthy
        end

        expect(@container.container_image.name).to eq("kubernetes/heapster")
        expect(@container.command).to eq("/heapster --source\\=kubernetes:https://kubernetes "\
                                                          "--sink\\=influxdb:http://monitoring-influxdb:80")

        @container2 = Container.find_by(:name => "influxdb")
        expect(@container2).to have_attributes(
          # :ems_ref       => "a7649eaa-e73f-11e4-b613-001a4a5f4a02_influxdb_kubernetes/heapster_influxdb:v0.3",
          :name          => "influxdb",
          :restart_count => 0
          # :backing_ref   => "docker://af741769b650a408f4a65d2d27043912b6d57e5e2a721faeb7a93a1989eef0c6"
        )

        # Check the relation to container group
        expect(@container2.container_group).to have_attributes(
          :name => "monitoring-influx-grafana-controller-22icy"
        )

        # Check relation to provider and container image
        expect(@container2.container_image.name).to eq("kubernetes/heapster_influxdb")
        expect(@container2.ext_management_system).to eq(ems)

        expect(@container.container_node).to have_attributes(
          :name => "10.35.0.169"
        )
      end

      def assert_specific_container_group(expected_extra_tags: [])
        @containergroup = ContainerGroup.find_by(:name => "monitoring-heapster-controller-4j5zu")
        expect(@containergroup).to have_attributes(
          # :ems_ref        => "49984e80-e1b7-11e4-b7dc-001a4a5f4a02",
          :name           => "monitoring-heapster-controller-4j5zu",
          :restart_policy => "Always",
          :dns_policy     => "ClusterFirst",
          :phase          => "Running"
        )
        expect(@containergroup.labels).to contain_exactly(
          label_with_name_value("name", "heapster")
        )
        expect(@containergroup.tags).to contain_exactly(
          tag_in_category_with_description(@name_category, "heapster"),
          *expected_extra_tags
        )

        # Check the relation to container node
        expect(@containergroup.container_node).not_to be_nil
        # @containergroup.container_node.should have_attributes(:ems_ref => "a3d2a008-e73f-11e4-b613-001a4a5f4a02")

        # Check the relation to container services
        @services = @containergroup.container_services
        expect(@services.count).to eq(1)
        expect(@services.first).to have_attributes(
          # :ems_ref => "49981230-e1b7-11e4-b7dc-001a4a5f4a02",
          :name         => "monitoring-heapster",
          :service_type => "ClusterIP"
        )

        # Check the relation to containers
        expect(@containergroup.containers.count).to eq(1)

        # Check relations to replicator, labels and provider
        expect(@containergroup.container_replicator).to eq(
          ContainerReplicator.find_by(:name => "monitoring-heapster-controller")
        )
        expect(@containergroup.container_replicator.labels).to contain_exactly(
          label_with_name_value("name", "heapster")
        )
        expect(@containergroup.ext_management_system).to eq(ems)

        # Check pod condition name is "Ready" with status "True"
        @containergroupconditions = ContainerCondition.where(:container_entity_type => "ContainerGroup")
        expect(@containergroupconditions.first).to have_attributes(
          :name   => "Ready",
          :status => "True"
        )
      end

      def assert_specific_container_node
        @containernode = ContainerNode.where(:name => "10.35.0.169").first
        expect(@containernode).to have_attributes(
          # :ems_ref       => "a3d2a008-e73f-11e4-b613-001a4a5f4a02",
          :lives_on_type              => openstack_vm.type,
          :lives_on_id                => openstack_vm.id,
          :container_runtime_version  => "docker://1.5.0",
          :kubernetes_kubelet_version => "v1.0.0-dirty",
          :kubernetes_proxy_version   => "v1.0.0-dirty",
          :max_container_groups       => 40
        )

        @containernodeconditions = ContainerCondition.where(:container_entity_type => "ContainerNode")
        expect(@containernodeconditions.count).to eq(2)
        expect(@containernodeconditions.first).to have_attributes(
          :name   => "Ready",
          :status => "True"
        )

        expect(@containernode.labels).to contain_exactly(
          label_with_name_value("kubernetes.io/hostname", "10.35.0.169")
        )

        expect(@containernode.computer_system.operating_system).to have_attributes(
          :distribution   => "Fedora 20 (Heisenbug)",
          :kernel_version => "3.18.9-100.fc20.x86_64"
        )

        expect(@containernode.hardware).to have_attributes(
          :cpu_total_cores => 2,
          :memory_mb       => 2000
        )

        expect(@containernode.ready_condition_status).not_to be_nil
        expect(@containernode.lives_on).to eq(openstack_vm)
        expect(@containernode.container_groups.count).to eq(2)
        expect(@containernode.ext_management_system).to eq(ems)

        # Leaving this test commented out until we find a way to test this more easily
        # Check relationship with oVirt provider
        @containernode = ContainerNode.where(:name => "localhost.localdomain").first
        expect(@containernode).to have_attributes(
          :lives_on_type => ovirt_vm.type,
          :lives_on_id   => ovirt_vm.id
        )
        expect(@containernode.lives_on).to eq(ovirt_vm)
        expect(@containernode.containers.count).to eq(0)
        expect(@containernode.container_routes.count).to eq(0)
      end

      def assert_specific_container_service
        @containersrv = ContainerService.find_by(:name => "kubernetes")
        expect(@containersrv).to have_attributes(
          # :ems_ref          => "a36a2858-e73f-11e4-b613-001a4a5f4a02",
          :name             => "kubernetes",
          :session_affinity => "None",
          :portal_ip        => "10.0.0.1"
        )
        expect(@containersrv.labels).to contain_exactly(
          label_with_name_value("provider", "kubernetes"),
          label_with_name_value("component", "apiserver")
        )
        expect(@containersrv.selector_parts.count).to eq(0)

        @confs = @containersrv.container_service_port_configs
        expect(@confs.count).to eq(1)
        @confs = @confs.first
        expect(@confs).to have_attributes(
          :name        => nil,
          :protocol    => "TCP",
          :port        => 443,
          :target_port => "443",
          :node_port   => nil
        )

        # Check group relation
        @groups = ContainerService.find_by(:name => "monitoring-influxdb-ui").container_groups
        expect(@groups.count).to eq(1)
        @group = @groups.first
        expect(@group).to have_attributes(
          # :ems_ref => "49b72714-e1b7-11e4-b7dc-001a4a5f4a02",
          # :name    => "monitoring-influx-grafana-controller-2toua"
          :restart_policy => "Always",
          :dns_policy     => "ClusterFirst"
        )

        expect(@containersrv.ext_management_system).to eq(ems)
        expect(@containersrv.container_nodes.count).to eq(0)
      end

      def assert_specific_container_replicator(expected_extra_tags: [])
        @replicator = ContainerReplicator.where(:name => "monitoring-influx-grafana-controller").first
        expect(@replicator).to have_attributes(
          :name             => "monitoring-influx-grafana-controller",
          :replicas         => 1,
          :current_replicas => 1
        )
        expect(@replicator.labels).to contain_exactly(
          label_with_name_value("name", "influxGrafana")
        )
        expect(@replicator.tags).to contain_exactly(
          tag_in_category_with_description(@name_category, "influxGrafana"),
          *expected_extra_tags
        )
        expect(@replicator.selector_parts.count).to eq(1)

        @group = ContainerGroup.where(:name => "monitoring-influx-grafana-controller-22icy").first
        expect(@group.container_replicator).not_to be_nil
        expect(@group.container_replicator.name).to eq("monitoring-influx-grafana-controller")
        expect(@replicator.ext_management_system).to eq(ems)

        expect(@replicator.container_nodes.count).to eq(1)
        expect(@replicator.container_nodes.first).to have_attributes(
          :name => "10.35.0.169"
        )
      end

      def assert_specific_container_project
        @container_pr = ContainerProject.find_by(:name => "default")
        expect(@container_pr).to have_attributes(
          :name         => "default",
          :display_name => nil
        )

        expect(@container_pr.container_groups.count).to eq(2)
        expect(@container_pr.container_replicators.count).to eq(2)
        expect(@container_pr.container_nodes.count).to eq(1)
        expect(@container_pr.container_services.count).to eq(5)
        expect(@container_pr.ext_management_system).to eq(ems)
      end

      def assert_specific_container_quota
        expect(ContainerQuota.where(:name => "my-resource-quota-scopes2-2").pluck(:deleted_on)).to eq([nil]) # exactly one, active.
        container_quota = ContainerQuota.find_by(:name => "my-resource-quota-scopes2-2")
        expect(container_quota.ems_created_on).to be_a(ActiveSupport::TimeWithZone)
        expect(container_quota.container_quota_scopes).to contain_exactly(
          an_object_having_attributes(:scope => "Terminating"),
          an_object_having_attributes(:scope => "NotBestEffort")
        )
        expect(container_quota.container_project.name).to eq("my-project-2")
      end

      def assert_specific_container_quota_item
        container_quota = ContainerQuota.find_by(:name => "my-resource-quota-scopes2-2")
        expect(container_quota.container_quota_items.count).to eq(3)
        cpu_item = container_quota.container_quota_items.find_by(:resource => 'requests.cpu')
        expect(cpu_item).to have_attributes(
          :quota_desired  => 5.7,
          :quota_enforced => 5.7,
          :quota_observed => 0.0
        )
      end

      def assert_modified_container_quota_item
        container_quota = ContainerQuota.find_by(:name => "my-resource-quota-scopes2-2")
        expect(container_quota.container_quota_items.count).to eq(3)

        cpu_items = container_quota.all_container_quota_items.where(:resource => 'requests.cpu')
        expect(cpu_items.archived.all).to contain_exactly(
          an_object_having_attributes(
            :quota_desired  => 5.7,
            :quota_enforced => 5.7,
            :quota_observed => 0.0
          )
        )
        expect(cpu_items.active.all).to contain_exactly(
          an_object_having_attributes(
            :quota_desired  => 5.701,
            :quota_enforced => 5.701,
            :quota_observed => 0.0
          )
        )
      end

      def assert_specific_container_limit
        container_limit = ContainerLimit.find_by(:name => "limits")
        container_limit.ems_created_on.kind_of?(ActiveSupport::TimeWithZone)
        expect(container_limit.container_limit_items.count).to eq(2)
        expect(container_limit.container_project.name).to eq("default")
        item = container_limit.container_limit_items.each { |x| x[:item_type] == 'Container' && x[:resource] == 'cpu' }[0]
        assert_specific_limit_item item
      end

      def assert_specific_limit_item(item)
        expect(item).to have_attributes(
          :max                     => nil,
          :min                     => nil,
          :default                 => "100m",
          :default_request         => nil,
          :max_limit_request_ratio => nil
        )
      end

      def assert_specific_container_image_and_registry
        @image = ContainerImage.where(:name => "kubernetes/heapster").first
        expect(@image).to have_attributes(
          :name      => "kubernetes/heapster",
          :tag       => "v0.16.0",
          :image_ref => "docker://example.com:1234/kubernetes/heapster@f79cf2701046bea8d5f1384f7efe79dd4d20620b3594fff5be39142fa862259d"
        )

        expect(@image.container_image_registry).not_to be_nil
        expect(@image.container_image_registry).to have_attributes(
          :host => "example.com",
          :port => "1234"
        )
        expect(@image.container_nodes.count).to eq(1)
      end

      def label_with_name_value(name, value)
        an_object_having_attributes(
          :section => 'labels', :source => 'kubernetes',
          :name => name, :value => value
        )
      end

      def tag_in_category_with_description(category, description)
        satisfy { |tag| tag.category == category && tag.classification.description == description }
      end

      context "when refreshing an empty DB" do
        # Recreation steps for the VCR cassettes can be found here:
        # https://github.com/ManageIQ/manageiq-providers-openshift/blob/master/spec/models/manageiq/providers/openshift/container_manager/refresher_spec.rb

        before(:each) do
          VCR.use_cassette("#{described_class.name.underscore}_before_deletions",
                           :allow_unused_http_interactions => true,
                           :match_requests_on              => [:path,]) do # , :record => :new_episodes) do
            EmsRefresh.refresh(ems)
          end

          # fake node that should get archived on later refresh
          FactoryBot.create(:container_node, :name => "node", :ems_id => ems.id)
        end

        let(:container_volumes_count) { 68 }
        let(:persintent_volumes_count) { 3 }
        let(:object_counts) do
          # using strings instead of actual model classes for compact rspec diffs
          {
            'ContainerNode'         => 2, # including the fake node
            'ContainerGroup'        => 22,
            'Container'             => 22,
            'ContainerService'      => 16,
            'ContainerQuota'        => 9,
            'ContainerQuotaScope'   => 9,
            'ContainerQuotaItem'    => 30,
            'ContainerLimit'        => 3,
            'ContainerLimitItem'    => 12,
            'PersistentVolume'      => persintent_volumes_count,
            'ContainerVolume'       => container_volumes_count + persintent_volumes_count,
            'PersistentVolumeClaim' => 6
          }
        end

        it "saves the objects in the DB" do
          actual_counts = object_counts.collect { |k, _| [k, k.constantize.count] }.to_h
          expect(actual_counts).to eq(object_counts)
          expect(ems.container_volumes.count).to eq(container_volumes_count)
          expect(ems.persistent_volumes.count).to eq(persintent_volumes_count)

          assert_specific_container_volume
          assert_specific_persistent_volume
          assert_specific_persistent_volume_claim
          assert_specific_container_quota
          assert_specific_container_quota_item
        end

        def assert_specific_container_volume
          # Not in template but typical.  TODO: add CV to template.
          @container_volume = ContainerVolume.find_by(:name => "my-pvc-pod-volume-2")
          expect(@container_volume).to have_attributes(
            :type       => "ContainerVolume",
            :claim_name => "my-persistentvolumeclaim-2"
          )
          expect(@container_volume.persistent_volume_claim).to eq(
            PersistentVolumeClaim.find_by(:name => "my-persistentvolumeclaim-2")
          )
          expect(@container_volume.parent_type).to eq('ContainerGroup')
          expect(@container_volume.parent.name).to eq("my-pod-2")
        end

        def assert_specific_persistent_volume
          # Not in template but typical.  TODO: add PV to template.
          @persistent_volume = PersistentVolume.find_by(:name => "my-persistentvolume-2")
          expect(@persistent_volume).to have_attributes(
            :type           => "PersistentVolume",
            :access_modes   => "ReadWriteOnce",
            :capacity       => {:storage => 10.megabytes},
            :common_path    => "/tmp/my-persistentvolume-2",
            :reclaim_policy => "Retain",
            :status_phase   => "Bound"
          )
          expect(@persistent_volume.parent).to eq(ems)
          expect(@persistent_volume.persistent_volume_claim.name).to eq("my-persistentvolumeclaim-2")

          # through shortcuts: PV -> PVC -> CVs -> ContainerGroups
          expect(@persistent_volume.container_volumes).to eq(
            [ContainerVolume.find_by(:name => "my-pvc-pod-volume-2")]
          )
          expect(@persistent_volume.container_groups.size).to eq(1)
          expect(@persistent_volume.container_groups[0].name).to eq("my-pod-2")
        end

        def assert_specific_persistent_volume_claim
          # Pending PVC (in template):
          @pending_pvc = PersistentVolumeClaim.find_by(:name => "my-persistentvolumeclaim-pending-2")
          expect(@pending_pvc).to have_attributes(
            :phase    => "Pending",
            :capacity => {} # requested 8Gi but not bound to PV => no capacity
          )
          expect(@pending_pvc.container_volumes.count).to eq(0)
          expect(@pending_pvc.persistent_volume).to eq(nil)

          # Bound PVC (TODO: not in template but typical):
          @bound_pvc = PersistentVolumeClaim.find_by(:name => "my-persistentvolumeclaim-2")
          expect(@bound_pvc).to have_attributes(
            :phase    => "Bound",
            :requests => {:storage => 8.megabytes},
            :capacity => {:storage => 10.megabytes}
          )
          expect(@bound_pvc.container_project.name).to eq("my-project-2")

          pv = PersistentVolume.find_by(:name => "my-persistentvolume-2")
          cv = ContainerVolume.find_by(:name => "my-pvc-pod-volume-2", :type => "ContainerVolume")
          expect(@bound_pvc.container_volumes).to contain_exactly(pv, cv)
          expect(@bound_pvc.persistent_volume).to eq(pv)
        end

        context "when refreshing non empty DB" do
          # After deleting resources in the cluster:
          # "my-project-0" - The whole project
          # "my-project-1" - All resources inside the project
          # "my-project-2" - "my-pod-2", label of "my-route-2", parameters of "my-template-2"

          before(:each) do
            VCR.use_cassette("#{described_class.name.underscore}_after_deletions",
                             :allow_unused_http_interactions => true,
                             :match_requests_on              => [:path,]) do # , :record => :new_episodes) do
              EmsRefresh.refresh(ems)
            end
          end

          it "removes the deleted objects from the DB" do
            deleted = {
              'ContainerService'      => 6,
              'ContainerLimit'        => 2,
              'ContainerLimitItem'    => 8,
              'PersistentVolume'      => 0,
              'PersistentVolumeClaim' => 4
            }
            expected_counts = deleted.collect { |k, d| [k, object_counts[k] - d] }.to_h
            actual_counts = expected_counts.collect { |k, _| [k, k.constantize.count] }.to_h
            expect(actual_counts).to eq(expected_counts)

            expect(ContainerService.find_by(:name => "my-service-0")).to be_nil
            expect(ContainerService.find_by(:name => "my-service-1")).to be_nil

            expect(ContainerLimit.find_by(:name => "my-limit-range-0")).to be_nil
            expect(ContainerLimit.find_by(:name => "my-limit-range-1")).to be_nil

            expect(PersistentVolumeClaim.find_by(:name => "my-persistentvolumeclaim-0")).to be_nil
            expect(PersistentVolumeClaim.find_by(:name => "my-persistentvolumeclaim-1")).to be_nil
          end

          it "archives & disconnects objects" do
            archived = {
              'ContainerNode'      => 1, # the fake node
              'ContainerGroup'     => 2 * 2 + 1,
              'Container'          => 2 * 2 + 1,
              'ContainerQuota'     => 2 * 3,
              'ContainerQuotaItem' => 2 * 10 + 2
            }
            added = {
              'ContainerQuotaItem' => 1
            }
            actual_archived = archived.collect { |k, _| [k, k.constantize.archived.count] }.to_h
            expect(actual_archived).to eq(archived)

            expected_active = archived.collect { |k, a| [k, object_counts[k] - a + added.fetch(k, 0)] }.to_h
            actual_active = archived.collect { |k, _| [k, k.constantize.active.count] }.to_h
            expect(actual_active).to eq(expected_active)

            expected_counts = archived.collect { |k, _| [k, object_counts[k] + added.fetch(k, 0)] }.to_h
            actual_counts = archived.collect { |k, _| [k, k.constantize.count] }.to_h
            expect(actual_counts).to eq(expected_counts)

            pod0 = ContainerGroup.find_by(:name => "my-pod-0")
            pod1 = ContainerGroup.find_by(:name => "my-pod-1")
            pod2 = ContainerGroup.find_by(:name => "my-pod-2")

            [pod0, pod1, pod2].each do |pod|
              assert_disconnected(pod)
              expect(pod.container_project).not_to be_nil
              expect(pod.containers.count).to eq(1)
              expect(pod.container_volumes.count).to eq(2) # default-token-*, my-pvc-pod-volume-2. TODO: test before deletions
            end
            # ContainerVolume records don't get archived themselves, but some belong to archived pods.
            expect(ContainerVolume.where(:type => 'ContainerVolume').count).to eq(container_volumes_count)
            expect(ems.container_volumes.count).to eq(container_volumes_count - 18)

            container0 = Container.find_by(:name => "my-container", :container_group => pod0)
            container1 = Container.find_by(:name => "my-container", :container_group => pod1)
            container2 = Container.find_by(:name => "my-container", :container_group => pod2)

            [container0, container1, container2].each do |container|
              expect(container).not_to be_nil
              assert_disconnected(container)
              expect(container.container_project).not_to be_nil
            end

            assert_specific_container_quota
            # All items of archived quotas are archived
            expect(ContainerQuotaItem.active.joins(:container_quota).merge(ContainerQuota.archived)).to be_empty
            # Archived items of alive quotas:
            archived_items = ContainerQuotaItem.archived.joins(:container_quota).merge(ContainerQuota.active)
            expect(archived_items.pluck(:resource)).to contain_exactly(
              'pods', # observed changed
              'requests.cpu' # requested changed
            )
            assert_modified_container_quota_item
          end
        end
      end

      def assert_disconnected(object)
        expect(object).not_to be_nil
        expect(object.deleted_on).not_to be_nil
        expect(object.archived?).to be true
      end
    end
  end

  context "Targeted refresh" do
    before { full_refresh }

    it "doesn't impact unassociated records" do
      after_full_refresh = serialize_inventory

      targeted_refresh(
        %w[pod node namespace service limit_range persistent_volume replication_controller resource_quota].map do |type|
          Kubeclient::Resource.new(:type => "MODIFIED", :object => load_watch_notice_data(type))
        end
      )

      assert_inventory_not_changed(after_full_refresh, serialize_inventory)
    end

    context "limit_ranges" do
      let(:new_limit_range) { load_watch_notice_data("new_limit_range") }
      let(:limit_range)     { load_watch_notice_data("limit_range") }

      it "created" do
        targeted_refresh([Kubeclient::Resource.new(:type => "ADDED", :object => new_limit_range)])
        expect(ems.container_limits.pluck(:ems_ref)).to include(new_limit_range.dig(:metadata, :uid))
      end

      it "updated" do
        limit_range[:spec][:limits][0][:default][:cpu]    = "200m"
        limit_range[:spec][:limits][0][:default][:memory] = "1024Mi"

        targeted_refresh([Kubeclient::Resource.new(:type => "MODIFIED", :object => limit_range)])

        container_limit = ems.container_limits.find_by(:ems_ref => limit_range.dig(:metadata, :uid))

        cpu_limit = container_limit.container_limit_items.find_by(:resource => "cpu")
        mem_limit = container_limit.container_limit_items.find_by(:resource => "memory")

        expect(cpu_limit.default).to eq("200m")
        expect(mem_limit.default).to eq("1024Mi")
      end

      it "deleted" do
        targeted_refresh([Kubeclient::Resource.new(:type => "DELETED", :object => limit_range)])
        expect(ems.container_limits.pluck(:ems_ref)).not_to include(limit_range.dig(:metadata, :uid))
      end
    end

    context "nodes" do
      let(:new_node) { load_watch_notice_data("node") }
      let(:node)     { load_watch_notice_data("node") }

      it "created" do
        targeted_refresh([Kubeclient::Resource.new(:type => "ADDED", :object => new_node)])
        expect(ems.container_nodes.pluck(:ems_ref)).to include(new_node.dig(:metadata, :uid))
      end

      it "updated" do
        node[:status][:capacity][:pods] = "100"
        targeted_refresh([Kubeclient::Resource.new(:type => "MODIFIED", :object => node)])
        expect(ems.container_nodes.find_by(:ems_ref => node.dig(:metadata, :uid)).max_container_groups).to eq(100)
      end

      it "deleted" do
        targeted_refresh([Kubeclient::Resource.new(:type => "DELETED", :object => node)])
        expect(ems.container_nodes.pluck(:ems_ref)).not_to include(node.dig(:metadata, :uid))
      end
    end

    context "persistent_volumes" do
      let(:new_pv) { load_watch_notice_data("new_persistent_volume") }
      let(:pv)     { load_watch_notice_data("persistent_volume") }

      it "created" do
        targeted_refresh([Kubeclient::Resource.new(:type => "ADDED", :object => new_pv)])
        expect(ems.persistent_volumes.pluck(:ems_ref)).to include(new_pv.dig(:metadata, :uid))
      end

      it "updated" do
        pv[:spec][:capacity][:storage] = "20Gi"
        targeted_refresh([Kubeclient::Resource.new(:type => "MODIFIED", :object => pv)])
        persistent_volume = ems.persistent_volumes.find_by(:ems_ref => pv.dig(:metadata, :uid))
        expect(persistent_volume.capacity[:storage]).to eq(20.gigabytes)
      end

      it "deleted" do
        targeted_refresh([Kubeclient::Resource.new(:type => "DELETED", :object => pv)])
        expect(ems.persistent_volumes.pluck(:ems_ref)).not_to include(pv.dig(:metadata, :uid))
      end
    end

    context "persistent_volume_claims" do
      let(:new_pvc) { load_watch_notice_data("new_persistent_volume_claim") }

      it "created" do
        targeted_refresh([Kubeclient::Resource.new(:type => "ADDED", :object => new_pvc)])
        expect(ems.persistent_volume_claims.pluck(:ems_ref)).to include(new_pvc.dig(:metadata, :uid))
      end

      # The VCR for full-refresh doesn't have any persistent volume claims so we
      # have to add a new one then modify/delete it
      it "updated" do
        targeted_refresh([Kubeclient::Resource.new(:type => "ADDED", :object => new_pvc)])
        targeted_refresh([Kubeclient::Resource.new(:type => "MODIFIED", :object => new_pvc)])
        expect(ems.persistent_volume_claims.pluck(:ems_ref)).to include(new_pvc.dig(:metadata, :uid))
      end

      it "deleted" do
        targeted_refresh([Kubeclient::Resource.new(:type => "ADDED", :object => new_pvc)])
        targeted_refresh([Kubeclient::Resource.new(:type => "DELETED", :object => new_pvc)])
        expect(ems.persistent_volume_claims.pluck(:ems_ref)).not_to include(new_pvc.dig(:metadata, :uid))
      end
    end

    context "pods" do
      let(:new_pod) { load_watch_notice_data("new_pod") }
      let(:pod)     { load_watch_notice_data("pod") }

      it "created" do
        targeted_refresh([Kubeclient::Resource.new(:type => "ADDED", :object => new_pod)])
        expect(ems.container_groups.pluck(:ems_ref)).to include(new_pod.dig(:metadata, :uid))
      end

      it "updated" do
        pod[:status][:phase] = "Failed"
        targeted_refresh([Kubeclient::Resource.new(:type => "MODIFIED", :object => pod)])
        expect(ems.container_groups.find_by(:ems_ref => pod.dig(:metadata, :uid)).phase).to eq("Failed")
      end

      it "deleted" do
        targeted_refresh([Kubeclient::Resource.new(:type => "DELETED", :object => pod)])
        expect(ems.container_groups.pluck(:ems_ref)).not_to include(pod.dig(:metadata, :uid))
      end
    end

    context "projects" do
      let(:new_namespace) { load_watch_notice_data("new_namespace") }
      let(:namespace)     { load_watch_notice_data("namespace") }

      it "created" do
        targeted_refresh([Kubeclient::Resource.new(:type => "ADDED", :object => new_namespace)])
        expect(ems.container_projects.pluck(:ems_ref)).to include(new_namespace.dig(:metadata, :uid))
      end

      it "updated" do
        namespace[:metadata][:name] = "my-not-as-new-project"
        targeted_refresh([Kubeclient::Resource.new(:type => "MODIFIED", :object => namespace)])
        expect(ems.container_projects.pluck(:name)).to include("my-not-as-new-project")
      end

      it "deleted" do
        targeted_refresh([Kubeclient::Resource.new(:type => "DELETED", :object => namespace)])
        expect(ems.container_projects.pluck(:ems_ref)).not_to include(namespace.dig(:metadata, :uid))
      end
    end

    context "replication_controllers" do
      let(:replication_controller)     { load_watch_notice_data("replication_controller") }
      let(:new_replication_controller) { load_watch_notice_data("new_replication_controller") }

      it "created" do
        targeted_refresh([Kubeclient::Resource.new(:type => "ADDED", :object => new_replication_controller)])
        expect(ems.container_replicators.pluck(:ems_ref)).to include(new_replication_controller.dig(:metadata, :uid))
      end

      it "updated" do
        replication_controller[:metadata][:name] = "monitoring-heapster-controller-updated"
        targeted_refresh([Kubeclient::Resource.new(:type => "MODIFIED", :object => replication_controller)])

        container_replicator = ems.container_replicators.find_by(:ems_ref => replication_controller[:metadata][:uid])
        expect(container_replicator.name).to eq("monitoring-heapster-controller-updated")
      end

      it "deleted" do
        targeted_refresh([Kubeclient::Resource.new(:type => "DELETED", :object => replication_controller)])
        expect(ems.container_replicators.pluck(:ems_ref)).not_to include(replication_controller.dig(:metadata, :uid))
      end
    end

    context "resource_quotas" do
      let(:resource_quota)     { load_watch_notice_data("resource_quota") }
      let(:new_resource_quota) { load_watch_notice_data("new_resource_quota") }

      it "created" do
        targeted_refresh([Kubeclient::Resource.new(:type => "ADDED", :object => new_resource_quota)])
        expect(ems.container_quotas.pluck(:ems_ref)).to include(new_resource_quota.dig(:metadata, :uid))
      end

      it "updated" do
        resource_quota[:spec][:hard][:cpu] = "40"
        targeted_refresh([Kubeclient::Resource.new(:type => "MODIFIED", :object => resource_quota)])

        quota = ems.container_quotas.find_by(:ems_ref => resource_quota[:metadata][:uid])
        expect(quota.container_quota_items.first.quota_desired).to eq(40)
      end

      it "deleted" do
        targeted_refresh([Kubeclient::Resource.new(:type => "DELETED", :object => resource_quota)])
        expect(ems.container_quotas.pluck(:ems_ref)).not_to include(resource_quota.dig(:metadata, :uid))
      end
    end

    context "services" do
      let(:new_service) { load_watch_notice_data("new_service") }
      let(:service)     { load_watch_notice_data("service") }

      it "created" do
        targeted_refresh([Kubeclient::Resource.new(:type => "ADDED", :object => new_service)])
        expect(ems.container_services.pluck(:ems_ref)).to include(new_service.dig(:metadata, :uid))
      end

      it "updated" do
        service[:spec][:clusterIP] = "10.0.0.116"
        targeted_refresh([Kubeclient::Resource.new(:type => "MODIFIED", :object => service)])

        container_service = ems.container_services.find_by(:ems_ref => service.dig(:metadata, :uid))
        expect(container_service.portal_ip).to eq("10.0.0.116")
        expect(container_service.reload.container_groups.count).to eq(1)
      end

      it "deleted" do
        targeted_refresh([Kubeclient::Resource.new(:type => "DELETED", :object => service)])
        expect(ems.container_services.pluck(:ems_ref)).not_to include(service.dig(:metadata, :uid))
      end
    end

    context "endpoints" do
      let(:endpoint) { load_watch_notice_data("endpoint") }

      it "created" do
        targeted_refresh([Kubeclient::Resource.new(:type => "ADDED", :object => endpoint)])
        expect(ems.container_services.pluck(:name)).to include(endpoint.dig(:metadata, :name))
      end

      it "updated" do
        endpoint[:subsets][0][:addresses] << {
          :ip        => "172.17.0.3",
          :targetRef => {
            :kind            => "Pod",
            :namespace       => "default",
            :name            => "monitoring-heapster-controller-4j5zu",
            :uid             => "1f60be5d-35f2-11e5-8917-001a4a5f4a00",
            :resourceVersion => "195"
          }
        }

        targeted_refresh([Kubeclient::Resource.new(:type => "MODIFIED", :object => endpoint)])

        container_project = ems.container_projects.find_by(:name => endpoint.dig(:metadata, :namespace))
        container_service = container_project.container_services.find_by(:name => endpoint.dig(:metadata, :name))

        expect(container_service.reload.container_groups.count).to eq(2)
      end

      it "deleted" do
        targeted_refresh([Kubeclient::Resource.new(:type => "DELETED", :object => endpoint)])
        expect(ems.container_services.pluck(:name)).to include(endpoint.dig(:metadata, :name))
      end
    end

    def targeted_refresh(notices)
      endpoint = Kubeclient::Resource.new(load_watch_notice_data("endpoint"))
      service  = Kubeclient::Resource.new(load_watch_notice_data("service"))

      kube = double("Kubeclient::Client")
      allow(kube).to receive(:get_endpoint).and_return(endpoint)
      allow(kube).to receive(:get_service).and_return(service)
      allow(ems).to receive(:connect).and_return(kube)

      collector = ManageIQ::Providers::Kubernetes::Inventory::Collector::WatchNotice.new(ems, notices)
      persister = ManageIQ::Providers::Kubernetes::Inventory::Persister::WatchNotice.new(ems, nil)
      parser    = ManageIQ::Providers::Kubernetes::Inventory::Parser::WatchNotice.new

      parser.collector = collector
      parser.persister = persister
      parser.parse
      persister.persist!
    end

    def load_watch_notice_data(type)
      YAML.load_file("spec/models/manageiq/providers/kubernetes/container_manager/watches_data/#{type}.yml")
    end
  end

  def full_refresh
    # VCR by default matches on :method and the whole :uri
    # In this case we are sending :limit in the :query section but we
    # want to simulate an older kube API that doesn't respond to that
    # param.  This can be done by having VCR ignore the :query component
    # of the URI and return the legacy style responses.
    VCR.use_cassette(described_class.name.underscore, :match_requests_on => [:method, :host, :path]) do # , :record => :new_episodes) do
      EmsRefresh.refresh(ems)
    end
    ems.reload
  end
end
