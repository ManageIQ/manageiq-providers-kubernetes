require 'recursive-open-struct'

describe ManageIQ::Providers::Kubernetes::Inventory::Parser::ContainerManager do
  let(:ems)       { FactoryBot.create(:ems_kubernetes) }
  let(:persister) { ManageIQ::Providers::Kubernetes::Inventory::Persister::ContainerManager.new(ems) }
  let(:parser)    { described_class.new.tap { |p| p.persister = persister } }

  describe "parse_namespace" do
    it "handles simple data" do
      parsed = parser.send(:parse_namespace,
        array_recursive_ostruct(
          :metadata => {
            :name              => "proj2",
            :selfLink          => "/api/v1/namespaces/proj2",
            :uid               => "554c1eaa-f4f6-11e5-b943-525400c7c086",
            :resourceVersion   => "150569",
            :creationTimestamp => "2016-03-28T15:04:13Z",
            :labels            => {:department => "Warp-drive"},
            :annotations       => {:"openshift.io/description"  => "",
                                   :"openshift.io/display-name" => "Project 2"}
          },
          :spec     => {:finalizers => ["openshift.io/origin", "kubernetes"]},
          :status   => {:phase => "Active"}
        )
      )

      expect(parsed.data).to include(
        :ems_ref          => "554c1eaa-f4f6-11e5-b943-525400c7c086",
        :name             => "proj2",
        :ems_created_on   => "2016-03-28T15:04:13Z",
        :resource_version => "150569",
      )

      custom_attributes_collection = persister.collections[[:custom_attributes_for, "ContainerProject", "labels"]]
      expect(custom_attributes_collection.data.map(&:data)).to include(
        a_hash_including(
          :section => "labels",
          :name    => "department",
          :value   => "Warp-drive",
          :source  => "kubernetes"
        )
      )

      taggings_collection = persister.collections[[:taggings_for, "ContainerProject"]]
      expect(taggings_collection.data.map(&:data)).to be_empty
    end
  end

  describe "parse_image_name" do
    digest = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    example_ref = "docker://#{digest}"
    example_images = [{:image_name => "example",
                       :image_ref  => example_ref,
                       :image      => {:name => "example", :tag => nil, :digest => digest,
                                       :image_ref => "docker://example@#{digest}"},
                       :registry   => nil},

                      {:image_name => "example",
                       :image_ref  => "docker://sha256:#{digest}",
                       :image      => {:name => "example", :tag => nil, :digest => "sha256:#{digest}",
                                       :image_ref => "docker://example@sha256:#{digest}"},
                       :registry   => nil},

                      {:image_name => "example:tag",
                       :image_ref  => example_ref,
                       :image      => {:name => "example", :tag => "tag", :digest => digest,
                                       :image_ref => "docker://example@#{digest}"},
                       :registry   => nil},

                      {:image_name => "user/example",
                       :image_ref  => example_ref,
                       :image      => {:name => "user/example", :tag => nil, :digest => digest,
                                       :image_ref => "docker://user/example@#{digest}"},
                       :registry   => nil},

                      {:image_name => "user/example:tag",
                       :image_ref  => example_ref,
                       :image      => {:name => "user/example", :tag => "tag", :digest => digest,
                                       :image_ref => "docker://user/example@#{digest}"},
                       :registry   => nil},

                      {:image_name => "example/subname/example",
                       :image_ref  => example_ref,
                       :image      => {:name => "example/subname/example", :tag => nil, :digest => digest,
                                       :image_ref => "docker://example/subname/example@#{digest}"},
                       :registry   => nil},

                      {:image_name => "example/subname/example:tag",
                       :image_ref  => example_ref,
                       :image      => {:name => "example/subname/example", :tag => "tag", :digest => digest,
                                       :image_ref => "docker://example/subname/example@#{digest}"},
                       :registry   => nil},

                      {:image_name => "host:1234/subname/example",
                       :image_ref  => example_ref,
                       :image      => {:name => "subname/example", :tag => nil, :digest => digest,
                                       :image_ref => "docker://host:1234/subname/example@#{digest}"},
                       :registry   => {:name => "host", :host => "host", :port => "1234"}},

                      {:image_name => "host:1234/subname/example:tag",
                       :image_ref  => example_ref,
                       :image      => {:name => "subname/example", :tag => "tag", :digest => digest,
                                       :image_ref => "docker://host:1234/subname/example@#{digest}"},
                       :registry   => {:name => "host", :host => "host", :port => "1234"}},

                      {:image_name => "host.com:1234/subname/example",
                       :image_ref  => example_ref,
                       :image      => {:name => "subname/example", :tag => nil, :digest => digest,
                                       :image_ref => "docker://host.com:1234/subname/example@#{digest}"},
                       :registry   => {:name => "host.com", :host => "host.com", :port => "1234"}},

                      {:image_name => "host.com:1234/subname/example:tag",
                       :image_ref  => example_ref,
                       :image      => {:name => "subname/example", :tag => "tag", :digest => digest,
                                       :image_ref => "docker://host.com:1234/subname/example@#{digest}"},
                       :registry   => {:name => "host.com", :host => "host.com", :port => "1234"}},

                      {:image_name => "host.com/subname/example",
                       :image_ref  => example_ref,
                       :image      => {:name => "subname/example", :tag => nil, :digest => digest,
                                       :image_ref => "docker://host.com/subname/example@#{digest}"},
                       :registry   => {:name => "host.com", :host => "host.com", :port => nil}},

                      {:image_name => "host.com/example",
                       :image_ref  => example_ref,
                       :image      => {:name => "example", :tag => nil, :digest => digest,
                                       :image_ref => "docker://host.com/example@#{digest}"},
                       :registry   => {:name => "host.com", :host => "host.com", :port => nil}},

                      {:image_name => "host.com:1234/subname/more/names/example:tag",
                       :image_ref  => example_ref,
                       :image      => {:name => "subname/more/names/example", :tag => "tag", :digest => digest,
                                       :image_ref => "docker://host.com:1234/subname/more/names/example@#{digest}"},
                       :registry   => {:name => "host.com", :host => "host.com", :port => "1234"}},

                      {:image_name => "localhost:1234/name",
                       :image_ref  => example_ref,
                       :image      => {:name => "name", :tag => nil, :digest => digest,
                                       :image_ref => "docker://localhost:1234/name@#{digest}"},
                       :registry   => {:name => "localhost", :host => "localhost", :port => "1234"}},

                      {:image_name => "localhost:1234/name@sha256:1234567abcdefg",
                       :image_ref  => example_ref,
                       :image      => {:name => "name", :tag => nil, :digest => "sha256:1234567abcdefg",
                                       :image_ref => "docker://localhost:1234/name@sha256:1234567abcdefg"},
                       :registry   => {:name => "localhost", :host => "localhost", :port => "1234"}},

                      # host with no port. more than one subdomain (a.b.c.com)
                      {:image_name => "reg.access.rh.com/openshift3/image-inspector",
                       :image_ref  => example_ref,
                       :image      => {:name => "openshift3/image-inspector", :tag => nil, :digest => digest,
                                       :image_ref => "docker://reg.access.rh.com/openshift3/image-inspector@#{digest}"},
                       :registry   => {:name => "reg.access.rh.com", :host => "reg.access.rh.com", :port => nil}},

                      # host with port. more than one subdomain (a.b.c.com:1234)
                      {:image_name => "host.access.com:1234/subname/more/names/example:tag",
                       :image_ref  => example_ref,
                       :image      => {:name => "subname/more/names/example", :tag => "tag", :digest => digest,
                                       :image_ref => "docker://host.access.com:1234/subname/more/names/example@#{digest}"},
                       :registry   => {:name => "host.access.com", :host => "host.access.com", :port => "1234"}},

                      # localhost no port
                      {:image_name => "localhost/name",
                       :image_ref  => example_ref,
                       :image      => {:name => "name", :tag => nil, :digest => digest,
                                       :image_ref => "docker://localhost/name@#{digest}"},
                       :registry   => {:name => "localhost", :host => "localhost", :port => nil}},

                      # tag and digest together
                      {:image_name => "reg.example.com:1234/name1:tagos@sha256:123abcdef",
                       :image_ref  => example_ref,
                       :image      => {:name => "name1", :tag => "tagos", :digest => "sha256:123abcdef",
                                       :image_ref => "docker://reg.example.com:1234/name1@sha256:123abcdef"},
                       :registry   => {:name => "reg.example.com", :host => "reg.example.com", :port => "1234"}},

                      # digest from new docker-pullable
                      {:image_name => "reg.example.com:1234/name1:tagos",
                       :image_ref  => "docker-pullable://reg.example.com:1234/name1@sha256:321bcd",
                       :image      => {:name => "name1", :tag => "tagos", :digest => "sha256:321bcd",
                                       :image_ref => "docker-pullable://reg.example.com:1234/name1@sha256:321bcd"},
                       :registry   => {:name => "reg.example.com", :host => "reg.example.com", :port => "1234"}},

                      # no image ref
                      {:image_name => "reg.example.com:1234/name1:tagos",
                       :image_ref  => "",
                       :image      => {:name => "name1", :tag => "tagos", :digest => nil,
                                       :image_ref => "docker://reg.example.com:1234/name1"},
                       :registry   => {:name => "reg.example.com", :host => "reg.example.com", :port => "1234"}},

                      # no image ref, digest in name
                      {:image_name => "reg.example.com:1234/name1:tagos@sha256:321bcd",
                       :image_ref  => "",
                       :image      => {:name => "name1", :tag => "tagos", :digest => "sha256:321bcd",
                                       :image_ref => "docker://reg.example.com:1234/name1@sha256:321bcd"},
                       :registry   => {:name => "reg.example.com", :host => "reg.example.com", :port => "1234"}},

                      {:image_name => "example@sha256:1234567abcdefg",
                       :image_ref  => example_ref,
                       :image      => {:name => "example", :tag => nil, :digest => "sha256:1234567abcdefg",
                                       :image_ref => "docker://example@sha256:1234567abcdefg"},
                       :registry   => nil},

                      {:image_name => "localhost:1234/name",
                       :image_ref  => nil,
                       :image      => nil,
                       :registry   => nil},

                      {:image_name => nil,
                       :image_ref  => example_ref,
                       :image      => nil,
                       :registry   => nil}]

    example_images.each do |ex|
      it "tests '#{ex[:image_name]}'" do
        result_image, result_registry = parser.send(:parse_image_name, ex[:image_name], ex[:image_ref])

        expect(result_image).to eq(ex[:image])
        expect(result_registry).to eq(ex[:registry])
      end
    end
  end

  describe "parse_pod" do
    # Several stages through which a pod goes, recorded from `oc get pods --watch --show-all -o json`.
    pod_common = {
      :apiVersion => "v1",
      :kind       => "Pod",
      :metadata   => {
        :annotations       => {
          :"openshift.io/scc" => "privileged"
        },
        :creationTimestamp => "2017-12-26T14:14:55Z",
        :labels            => {
          :"key-pod-label" => "value-pod-label"
        },
        :name              => "my-pod-0",
        :namespace         => "my-project-0",
        # :resourceVersion => ...
        :selfLink          => "/api/v1/namespaces/my-project-0/pods/my-pod-0",
        :uid               => "25da2bc6-ea47-11e7-a091-c6d6ab00a8c4"
      },
      :spec       => {
        :containers                    => [
          {
            :image                    => "registry.access.redhat.com/jboss-decisionserver-6/decisionserver63-openshift",
            :imagePullPolicy          => "Always",
            :name                     => "my-container",
            :ports                    => [
              {
                :containerPort => 6379,
                :protocol      => "TCP"
              }
            ],
            :resources                => {},
            :securityContext          => {
              :privileged     => true,
              :seLinuxOptions => {
                :level => "s0:c123,c456",
                :role  => "admin",
                :type  => "default",
                :user  => "username"
              }
            },
            :terminationMessagePath   => "/dev/termination-log",
            :terminationMessagePolicy => "File",
            :volumeMounts             => [
              {
                :mountPath => "/var/run/secrets/kubernetes.io/serviceaccount",
                :name      => "default-token-dss72",
                :readOnly  => true
              }
            ]
          }
        ],
        :dnsPolicy                     => "ClusterFirst",
        :imagePullSecrets              => [
          {
            :name => "default-dockercfg-975qh"
          }
        ],
        :restartPolicy                 => "Always",
        :schedulerName                 => "default-scheduler",
        :securityContext               => {},
        :serviceAccount                => "default",
        :serviceAccountName            => "default",
        :terminationGracePeriodSeconds => 30,
        :volumes                       => [
          {
            :name   => "default-token-dss72",
            :secret => {
              :defaultMode => 420,
              :secretName  => "default-token-dss72"
            }
          }
        ]
      },
      :status     => {
        :phase    => "Pending",
        :qosClass => "BestEffort"
      }
    }

    just_created_pod = pod_common.deep_merge(
      :metadata => {:resourceVersion => "11523"},
    )

    scheduled_pod = pod_common.deep_merge(
      :metadata => {:resourceVersion => "11526"},
      :spec     => {:nodeName => "localhost"}, # Yes! Scheduler mutates spec.
      :status   => {
        :conditions => [
          {
            :lastProbeTime      => nil,
            :lastTransitionTime => "2017-12-26T14:14:55Z",
            :status             => "True",
            :type               => "PodScheduled"
          }
        ],
      }
    )

    container_creating_pod = pod_common.deep_merge(
      :metadata => {:resourceVersion => "11534"},
      :spec     => {:nodeName => "localhost"},
      :status   => {
        :conditions        => [
          {
            :lastProbeTime      => nil,
            :lastTransitionTime => "2017-12-26T14:14:55Z",
            :status             => "True",
            :type               => "Initialized"
          },
          {
            :lastProbeTime      => nil,
            :lastTransitionTime => "2017-12-26T14:14:55Z",
            :message            => "containers with unready status: [my-container]",
            :reason             => "ContainersNotReady",
            :status             => "False",
            :type               => "Ready"
          },
          {
            :lastProbeTime      => nil,
            :lastTransitionTime => "2017-12-26T14:14:55Z",
            :status             => "True",
            :type               => "PodScheduled"
          }
        ],
        :containerStatuses => [
          {
            :image        => "registry.access.redhat.com/jboss-decisionserver-6/decisionserver63-openshift",
            :imageID      => "",
            :lastState    => {},
            :name         => "my-container",
            :ready        => false,
            :restartCount => 0,
            :state        => {
              :waiting => {
                :reason => "ContainerCreating"
              }
            }
          }
        ],
        :hostIP            => "10.0.2.15",
        :startTime         => "2017-12-26T14:14:55Z"
      }
    )

    # Following statuses stitched together from other pods but never mind.
    err_pod = container_creating_pod.deep_merge(
      :metadata          => {:resourceVersion => "11750"},
      :containerStatuses => [
        {
          :image        => "registry.access.redhat.com/no-such-image",
          :imageID      => "",
          :lastState    => {},
          :name         => "my-container",
          :ready        => false,
          :restartCount => 0,
          :state        => {
            :waiting => {
              :message => "rpc error: code = 2 desc = Error response from daemon: {\"message\":\"unknown: Not Found\"}",
              :reason  => "ErrImagePull"
            }
          }
        }
      ],
      # same :hostIP => "10.0.2.15", but now we also got podIP.  Successfully "running" pods also get podIP.
      :podIP             => "172.17.0.9",
    )

    graceful_deletion_pod = err_pod.deep_merge(
      :metadata => {
        :resourceVersion            => "11831",
        :deletionGracePeriodSeconds => 30,
        :deletionTimestamp          => "2017-12-26T14:15:06Z",
      },
    )

    deleted_pod = graceful_deletion_pod.deep_merge(
      :metadata          => {
        :resourceVersion => "11833",
        # :deletionGracePeriodSeconds, :deletionTimestamp unchanged.
      },
      :containerStatuses => [
        {
          :image        => "registry.access.redhat.com/no-such-image",
          :imageID      => "",
          :lastState    => {},
          :name         => "my-container",
          :ready        => false,
          :restartCount => 0,
          :state        => {
            :terminated => {
              :exitCode   => 0, # despite it never having run (image pull failed)!
              :finishedAt => nil,
              :startedAt  => nil
            }
          }
        }
      ],
    )

    pod_states = {
      "just_created_pod"       => just_created_pod,
      "scheduled_pod"          => scheduled_pod,
      "container_creating_pod" => container_creating_pod,
      "err_pod"                => err_pod,
      "graceful_deletion_pod"  => graceful_deletion_pod,
      "deleted_pod"            => deleted_pod
    }

    pod_states.each do |name, data|
      it "sets correct STI types for #{name}" do
        result = parser.send(:parse_pod, array_recursive_ostruct(data)).data

        expect(result[:type]).to eq('ManageIQ::Providers::Kubernetes::ContainerManager::ContainerGroup')

        # https://bugzilla.redhat.com/show_bug.cgi?id=1517676
        expect(persister.containers.data.collect { |c| c.data[:type] }.uniq).to eq(['ManageIQ::Providers::Kubernetes::ContainerManager::Container'])
      end
    end
  end

  describe "parse_container_state" do
    # check https://bugzilla.redhat.com/show_bug.cgi?id=1383498
    it "handles nil input" do
      expect(parser.send(:parse_container_state, nil)).to eq({})
    end
  end

  describe "parse_container_status" do
    let(:image)   { "abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ" }
    let(:imageID) { "docker://#{image}" }
    let(:pod_id)  { "af3d1a10-23d3-11e5-44c0-0af3d1a10370e" }

    it "handles invalid image" do
      container = array_recursive_ostruct(:image => nil, :imageID => imageID)
      expect(parser.send(:parse_container_status, container, pod_id)).to be_nil
    end

    it "handles invalid imageID" do
      container = array_recursive_ostruct(:image => image, :imageID => nil)
      expect(parser.send(:parse_container_status, container, pod_id)).to be_nil
    end
  end

  describe "parse_volumes" do
    example_volumes = [
      {
        :volume                => array_recursive_ostruct(:name    => "example-volume1",
                                                          :gitRepo => {:repository => "default-git-repository"}),
        :name                  => "example-volume1",
        :git_repository        => "default-git-repository",
        :empty_dir_medium_type => nil,
        :gce_pd_name           => nil,
        :common_fs_type        => nil,
        :common_path           => nil,
        :common_read_only      => nil,
        :common_secret         => nil,
        :common_volume_id      => nil,
        :common_partition      => nil
      },
      {
        :volume                => array_recursive_ostruct(:name     => "example-volume2",
                                                          :emptyDir => {:medium => "default-medium"}),
        :name                  => "example-volume2",
        :git_repository        => nil,
        :empty_dir_medium_type => "default-medium",
        :gce_pd_name           => nil,
        :common_fs_type        => nil,
        :common_path           => nil,
        :common_read_only      => nil,
        :common_secret         => nil,
        :common_volume_id      => nil,
        :common_partition      => nil
      },
      {
        :volume                => array_recursive_ostruct(:name              => "example-volume3",
                                                          :gcePersistentDisk => {:pdName => "example-pd-name",
                                                                                 :fsType => "default-fs-type"}),
        :name                  => "example-volume3",
        :git_repository        => nil,
        :empty_dir_medium_type => nil,
        :gce_pd_name           => "example-pd-name",
        :common_fs_type        => "default-fs-type",
        :common_path           => nil,
        :common_read_only      => nil,
        :common_secret         => nil,
        :common_volume_id      => nil,
        :common_partition      => nil
      },
      {
        :volume                => array_recursive_ostruct(:name                 => "example-volume4",
                                                          :awsElasticBlockStore => {:fsType => "example-fs-type"}),
        :name                  => "example-volume4",
        :git_repository        => nil,
        :empty_dir_medium_type => nil,
        :gce_pd_name           => nil,
        :common_fs_type        => "example-fs-type",
        :common_path           => nil,
        :common_read_only      => nil,
        :common_secret         => nil,
        :common_volume_id      => nil,
        :common_partition      => nil
      },
      {
        :volume                => array_recursive_ostruct(:name => "example-volume5",
                                                          :nfs  => {:path     => "example-path",
                                                                    :readOnly => true}),
        :name                  => "example-volume5",
        :git_repository        => nil,
        :empty_dir_medium_type => nil,
        :gce_pd_name           => nil,
        :common_fs_type        => nil,
        :common_path           => "example-path",
        :common_read_only      => true,
        :common_secret         => nil,
        :common_volume_id      => nil,
        :common_partition      => nil
      },
      {
        :volume                => array_recursive_ostruct(:name     => "example-volume6",
                                                          :hostPath => {:path => "default-path"}),
        :name                  => "example-volume6",
        :git_repository        => nil,
        :empty_dir_medium_type => nil,
        :gce_pd_name           => nil,
        :common_fs_type        => nil,
        :common_path           => "default-path",
        :common_read_only      => nil,
        :common_secret         => nil,
        :common_volume_id      => nil,
        :common_partition      => nil
      },
      {
        :volume                => array_recursive_ostruct(:name => "example-volume7",
                                                          :rbd  => {:fsType   => "user-fs-type",
                                                                    :readOnly => false}),
        :name                  => "example-volume7",
        :git_repository        => nil,
        :empty_dir_medium_type => nil,
        :gce_pd_name           => nil,
        :common_fs_type        => "user-fs-type",
        :common_path           => nil,
        :common_read_only      => false,
        :common_secret         => nil,
        :common_volume_id      => nil,
        :common_partition      => nil
      },
      {
        :volume                => array_recursive_ostruct(:name   => "example-volume8",
                                                          :secret => {:secretName => "example-secret"}),
        :name                  => "example-volume8",
        :git_repository        => nil,
        :empty_dir_medium_type => nil,
        :gce_pd_name           => nil,
        :common_fs_type        => nil,
        :common_path           => nil,
        :common_read_only      => nil,
        :common_secret         => "example-secret",
        :common_volume_id      => nil,
        :common_partition      => nil
      },
      {
        :volume                => array_recursive_ostruct(:name   => "example-volume9",
                                                          :cinder => {:volumeId => "example-id"}),
        :name                  => "example-volume9",
        :git_repository        => nil,
        :empty_dir_medium_type => nil,
        :gce_pd_name           => nil,
        :common_fs_type        => nil,
        :common_path           => nil,
        :common_read_only      => nil,
        :common_secret         => nil,
        :common_volume_id      => "example-id",
        :common_partition      => nil
      },
      {
        :volume                => array_recursive_ostruct(:name              => "example-volume10",
                                                          :gcePersistentDisk => {:partition => "default-partition"}),
        :name                  => "example-volume10",
        :git_repository        => nil,
        :empty_dir_medium_type => nil,
        :gce_pd_name           => nil,
        :common_fs_type        => nil,
        :common_path           => nil,
        :common_read_only      => nil,
        :common_secret         => nil,
        :common_volume_id      => nil,
        :common_partition      => "default-partition"
      }
    ]

    pod = array_recursive_ostruct(
      :metadata => {
        :name              => 'test-pod',
        :namespace         => 'test-namespace',
        :uid               => 'af3d1a10-23d3-11e5-44c0-0af3d1a10370e',
        :resourceVersion   => '3691041',
        :creationTimestamp => '2015-08-17T09:16:46Z',
      },
      :spec     => {
        :volumes => example_volumes.collect { |ex| ex[:volume] }
      }
    )

    it "tests example volumes" do
      parsed_volumes = parser.send(:parse_volumes, pod)

      example_volumes.zip(parsed_volumes).each do |example, parsed|
        expect(parsed).to include(
          :name                  => example[:name],
          :git_repository        => example[:git_repository],
          :empty_dir_medium_type => example[:empty_dir_medium_type],
          :gce_pd_name           => example[:gce_pd_name],
          :common_fs_type        => example[:common_fs_type],
          :common_path           => example[:common_path],
          :common_read_only      => example[:common_read_only],
          :common_secret         => example[:common_secret],
          :common_volume_id      => example[:common_volume_id],
          :common_partition      => example[:common_partition]
        )
      end
    end
  end

  describe "parse_iec_number" do
    it "parse capacity hash correctly" do
      hash = {:storage => "10Gi", :foo => "10"}
      expect(parser.send(:parse_resource_list, hash)).to eq({:storage => 10.gigabytes, :foo => 10})
    end

    it "parse capacity hash with bad value correctly" do
      hash = {:storage => "10Gi", :foo => "10wrong"}
      expect(parser.send(:parse_resource_list, hash)).to eq({:storage => 10.gigabytes})
    end
  end

  describe "quota parsing" do
    it "handles simple data" do
      resource_quota = parser.send(
        :parse_resource_quota,
        array_recursive_ostruct(
          :metadata => {
            :name              => 'test-quota',
            :namespace         => 'test-namespace',
            :uid               => 'af3d1a10-44c0-11e5-b186-0aaeec44370e',
            :resourceVersion   => '165339',
            :creationTimestamp => '2015-08-17T09:16:46Z',
          },
          :spec     => {
            :hard   => {
              :cpu    => '30',
              :pods   => '100',
              :memory => '10M'
            },
            :scopes => [
              "Terminating",
              "NotBestEffort"
            ]
          },
          :status   => {
            :hard => {
              :cpu    => '30',
              :pods   => '50',
              :memory => '100Mi'
            },
            :used => {
              :cpu    => '100m',
              :pods   => '50',
              :memory => '1.3e5'
            }
          }
        )
      )

      expect(resource_quota.data).to include(
        :name             => 'test-quota',
        :ems_ref          => 'af3d1a10-44c0-11e5-b186-0aaeec44370e',
        :ems_created_on   => '2015-08-17T09:16:46Z',
        :resource_version => '165339',
        :namespace        => 'test-namespace'
      )

      expect(persister.container_quota_scopes.data.map(&:data)).to include(
        a_hash_including(:scope => "Terminating"),
        a_hash_including(:scope => "NotBestEffort")
      )

      expect(persister.container_quota_items.data.map(&:data)).to include(
        a_hash_including(
          :resource       => "cpu",
          :quota_desired  => 30,
          :quota_enforced => 30,
          :quota_observed => 0.1
        ),
        a_hash_including(
          :resource       => "pods",
          :quota_desired  => 100,
          :quota_enforced => 50,
          :quota_observed => 50
        ),
        a_hash_including(
          :resource       => "memory",
          :quota_desired  => 10_000_000,
          :quota_enforced => 104_857_600,
          :quota_observed => 130_000
        )
      )
    end

    it "handles quotas with no specification" do
      quota = parser.send(:parse_resource_quota,
        array_recursive_ostruct(
          :metadata => {
            :name              => 'test-quota',
            :namespace         => 'test-namespace',
            :uid               => 'af3d1a10-44c0-11e5-b186-0aaeec44370e',
            :resourceVersion   => '165339',
            :creationTimestamp => '2015-08-17T09:16:46Z',
          },
          :spec     => {},
          :status   => {}
        )).data

      expect(quota).to include(
        :name             => 'test-quota',
        :ems_ref          => 'af3d1a10-44c0-11e5-b186-0aaeec44370e',
        :ems_created_on   => '2015-08-17T09:16:46Z',
        :resource_version => '165339',
        :namespace        => 'test-namespace'
      )
    end

    it "handles quotas with no status" do
      quota = parser.send(:parse_resource_quota,
        array_recursive_ostruct(
          :metadata => {
            :name              => 'test-quota',
            :namespace         => 'test-namespace',
            :uid               => 'af3d1a10-44c0-11e5-b186-0aaeec44370e',
            :resourceVersion   => '165339',
            :creationTimestamp => '2015-08-17T09:16:46Z'},
          :spec     => {
            :hard => {
              :cpu => '30'
            }
          },
          :status   => {}
        )
      ).data

      expect(quota).to include(
        :name             => 'test-quota',
        :ems_ref          => 'af3d1a10-44c0-11e5-b186-0aaeec44370e',
        :ems_created_on   => '2015-08-17T09:16:46Z',
        :resource_version => '165339',
        :namespace        => 'test-namespace',
      )

      expect(persister.container_quota_scopes.data).to be_empty
      expect(persister.container_quota_items.data.first.data).to include(
        :resource       => "cpu",
        :quota_desired  => 30,
        :quota_enforced => nil,
        :quota_observed => nil
      )
    end
  end

  describe "limit range parsing" do
    it "handles all limit types" do
      from_k8s = {
        :metadata => {
          :name              => 'test-range',
          :namespace         => 'test-namespace',
          :uid               => 'af3d1a10-44c0-11e5-b186-0aaeec44370e',
          :resourceVersion   => '2',
          :creationTimestamp => '2015-08-17T09:16:46Z',
        },
        :spec     => {
          :limits => [
            {
              :type => 'Container',
            }
          ]
        },
      }

      parsed = {
        :name                  => 'test-range',
        :ems_ref               => 'af3d1a10-44c0-11e5-b186-0aaeec44370e',
        :ems_created_on        => '2015-08-17T09:16:46Z',
        :resource_version      => '2',
        :namespace             => 'test-namespace'
      }

      %w(min max default defaultRequest maxLimitRequestRatio).each do |k8s_name|
        from_k8s[:spec][:limits][0][k8s_name.to_sym] = {:cpu => '512Mi'}
        #parsed[:container_limit_items][0][k8s_name.underscore.to_sym] = '512Mi'
        # note each iteration ADDS ANOTHER limit type to data & result
        range = parser.send(:parse_range, array_recursive_ostruct(from_k8s))
        expect(range.data).to include(parsed)

        expect(persister.container_limit_items.data.map(&:data)).to include(
          a_hash_including(
            :item_type               => "Container",
            :resource                => "cpu",
            :max                     => nil,
            :min                     => "512Mi",
            :default                 => nil,
            :default_request         => nil,
            :max_limit_request_ratio => nil
          )
        )
      end
    end

    it "handles missing limits specification" do
      metadata = {
        :name              => 'test-range',
        :namespace         => 'test-namespace',
        :uid               => 'af3d1a10-44c0-11e5-b186-0aaeec44370e',
        :resourceVersion   => '2',
        :creationTimestamp => '2015-08-17T09:16:46Z',
      }
      ranges = [
        {:metadata => metadata},
        {:metadata => metadata, :spec => nil},
        {:metadata => metadata, :spec => {}},
        {:metadata => metadata, :spec => {:limits => nil}},
        {:metadata => metadata, :spec => {:limits => []}}
      ]
      parsed = {
        :name                  => 'test-range',
        :ems_ref               => 'af3d1a10-44c0-11e5-b186-0aaeec44370e',
        :ems_created_on        => '2015-08-17T09:16:46Z',
        :resource_version      => '2',
        :namespace             => 'test-namespace',
      }
      ranges.each do |range|
        expect(parser.send(:parse_range, array_recursive_ostruct(range)).data).to include(parsed)
      end
    end
  end

  describe "parse_container_image" do
    shared_image_without_host = "shared/image"
    shared_image_with_host = "host:1234/shared/image"
    shared_ref = "docker-pullable://host:1234/repo/image@sha256:123456"
    other_registry_ref = "docker-pullable://other-host:4321/repo/image@sha256:123456"
    unique_ref = "docker-pullable://host:1234/repo/image@sha256:abcdef"

    it "returns unique object *identity* for same image but different digest" do
      [shared_image_with_host, shared_image_without_host].each do |shared_image|
        first_obj  = parser.parse_container_image(shared_image, shared_ref)
        second_obj = parser.parse_container_image(shared_image, unique_ref)

        expect(first_obj).not_to be(second_obj)
      end
    end

    it "returns unique object *content* for same image but different digest" do
      [shared_image_with_host, shared_image_without_host].each do |shared_image|
        first_obj  = parser.parse_container_image(shared_image, shared_ref)
        second_obj = parser.parse_container_image(shared_image, unique_ref)

        expect(first_obj).not_to eq(second_obj)
      end
    end

    it "returns same object *identity* for same digest" do
      [shared_image_with_host, shared_image_without_host].each do |shared_image|
        first_obj  = parser.parse_container_image(shared_image, shared_ref)
        second_obj = parser.parse_container_image(shared_image, shared_ref)

        expect(first_obj).to be(second_obj)
      end
    end

    it "returns same object *identity* for same digest and different repo" do
      [shared_image_with_host, shared_image_without_host].each do |shared_image|
        first_obj  = parser.parse_container_image(shared_image, other_registry_ref)
        second_obj = parser.parse_container_image(shared_image, shared_ref)

        expect(first_obj).to be(second_obj)
      end
    end

    it "returns existing image or nil with store_new_images=false" do
      obj1 = parser.parse_container_image(shared_image_without_host, shared_ref)
      obj2 = parser.parse_container_image(shared_image_without_host, shared_ref, :store_new_images => false)
      obj3 = parser.parse_container_image(shared_image_without_host, unique_ref, :store_new_images => false)
      expect(obj1).not_to be nil
      expect(obj2).to be obj2
      expect(obj3).to be nil
    end
  end

  describe "cross_link_node" do
    context "expected failures" do
      before :each do
        @node = OpenStruct.new(
          :identity_system => "f0c1fe7e-9c09-11e5-bb22-28d2447dcefe",
        )
      end

      after :each do
        parser.send(:cross_link_node, @node)
        expect(@node[:lives_on_id]).to eq(nil)
        expect(@node[:lives_on_type]).to eq(nil)
      end

      it "fails when provider type is wrong" do
        @node[:identity_infra] = "aws://aws_project/europe-west1/instance_id/"
        @ems = FactoryBot.create(:ems_google,
                                  :provider_region => "europe-west1",
                                  :project         => "aws_project")
        @vm = FactoryBot.create(:vm_google,
                                 :ext_management_system => @ems,
                                 :name                  => "instance_id")
      end
    end

    context "succesful attempts" do
      before :each do
        @node = OpenStruct.new(
          :identity_system => "f0c1fe7e-9c09-11e5-bb22-28d2447dcefe",
        )
      end

      after :each do
        parser.send(:cross_link_node, @node)
        expect(@node[:lives_on_id]).to eq(@vm.id)
        expect(@node[:lives_on_type]).to eq(@vm.type)
      end

      it "cross links google" do
        @node[:identity_infra] = "gce://gce_project/europe-west1/instance_id/"
        @ems = FactoryBot.create(:ems_google,
                                  :provider_region => "europe-west1",
                                  :project         => "gce_project")
        @vm = FactoryBot.create(:vm_google,
                                 :ext_management_system => @ems,
                                 :name                  => "instance_id")
      end

      it "cross links amazon" do
        @node[:identity_infra] = "aws:///us-west-1/aws-id"
        @ems = FactoryBot.create(:ems_amazon,
                                  :provider_region => "us-west-1")
        @vm = FactoryBot.create(:vm_amazon,
                                 :uid_ems               => "aws-id",
                                 :ext_management_system => @ems)
      end

      it "cross links openstack through provider id" do
        @node[:identity_infra] = "openstack:///openstack_id"
        @ems = FactoryBot.create(:ems_openstack)
        @vm = FactoryBot.create(:vm_openstack,
                                 :uid_ems               => 'openstack_id',
                                 :ext_management_system => @ems)
      end

      it 'cross links with missing data in ProviderID' do
        @node[:identity_infra] = "gce:////instance_id/"
        @ems = FactoryBot.create(:ems_google,
                                  :provider_region => "europe-west1",
                                  :project         => "gce_project")
        @vm = FactoryBot.create(:vm_google,
                                 :ext_management_system => @ems,
                                 :name                  => "instance_id")
      end

      it 'cross links with malformed provider id' do
        @node[:identity_infra] = "gce://instance_id"
        @ems = FactoryBot.create(:ems_google,
                                  :provider_region => "europe-west1",
                                  :project         => "gce_project")
        @vm = FactoryBot.create(:vm_google,
                                 :ext_management_system => @ems,
                                 :name                  => "instance_id")
      end

      it "cross links by uuid" do
        @node[:identity_infra] = nil
        @ems = FactoryBot.create(:ems_openstack)
        @vm = FactoryBot.create(:vm_openstack,
                                 :uid_ems               => @node[:identity_system],
                                 :ext_management_system => @ems)
      end
    end
  end

  describe "parse_node" do
    it "handles node without capacity" do
      expect(parser.send(
        :parse_node,
        array_recursive_ostruct(
          :metadata => {
            :name              => 'test-node',
            :uid               => 'f0c1fe7e-9c09-11e5-bb22-28d2447dcefe',
            :resourceVersion   => '369104',
            :creationTimestamp => '2015-12-06T11:10:21Z'
          },
          :spec     => {
            :providerID => 'aws:///zone/aws-id'
          },
          :status   => {
            :nodeInfo => {
              :machineID  => 'id',
              :systemUUID => 'uuid'
            }
          }
        )
      ).data).to include({
        :name                       => 'test-node',
        :ems_ref                    => 'f0c1fe7e-9c09-11e5-bb22-28d2447dcefe',
        :ems_created_on             => '2015-12-06T11:10:21Z',
        :container_runtime_version  => nil,
        :identity_infra             => 'aws:///zone/aws-id',
        :identity_machine           => 'id',
        :identity_system            => 'uuid',
        :kubernetes_kubelet_version => nil,
        :kubernetes_proxy_version   => nil,
        :lives_on_id                => nil,
        :lives_on_type              => nil,
        :max_container_groups       => nil,
        :resource_version           => '369104',
        :type                       => 'ManageIQ::Providers::Kubernetes::ContainerManager::ContainerNode',
      })
    end

    it "handles node without providerID, memory, cpu and pods" do
      expect(parser.send(
        :parse_node,
        array_recursive_ostruct(
          :metadata => {
            :name              => 'test-node',
            :uid               => 'f0c1fe7e-9c09-11e5-bb22-28d2447dcefe',
            :resourceVersion   => '3691041',
            :creationTimestamp => '2015-12-06T11:10:21Z'
          },
          :spec     => {
            :externalID => '10.35.17.99'
          },
          :status   => {
            :nodeInfo => {
              :machineID  => 'id',
              :systemUUID => 'uuid'
            },
            :capacity => {}
          }
        )
      ).data).to include({
        :name                       => 'test-node',
        :ems_ref                    => 'f0c1fe7e-9c09-11e5-bb22-28d2447dcefe',
        :ems_created_on             => '2015-12-06T11:10:21Z',
        :container_runtime_version  => nil,
        :identity_infra             => nil,
        :identity_machine           => 'id',
        :identity_system            => 'uuid',
        :kubernetes_kubelet_version => nil,
        :kubernetes_proxy_version   => nil,
        :lives_on_id                => nil,
        :lives_on_type              => nil,
        :max_container_groups       => nil,
        :resource_version           => '3691041',
        :type                       => 'ManageIQ::Providers::Kubernetes::ContainerManager::ContainerNode',
      })
    end

    it "handles node without nodeInfo" do
      expect(parser.send(
        :parse_node,
        array_recursive_ostruct(
          :metadata => {
            :name              => 'test-node',
            :uid               => 'f0c1fe7e-9c09-11e5-bb22-28d2447dcefe',
            :resourceVersion   => '369104',
            :creationTimestamp => '2016-01-01T11:10:21Z'
          },
          :spec     => {
            :providerID => 'aws:///zone/aws-id'
          },
          :status   => {
            :capacity => {}
          }
        )
      ).data).to include(
        {
          :name                 => 'test-node',
          :ems_ref              => 'f0c1fe7e-9c09-11e5-bb22-28d2447dcefe',
          :ems_created_on       => '2016-01-01T11:10:21Z',
          :identity_infra       => 'aws:///zone/aws-id',
          :lives_on_id          => nil,
          :lives_on_type        => nil,
          :max_container_groups => nil,
          :resource_version      => '369104',
          :type                  => 'ManageIQ::Providers::Kubernetes::ContainerManager::ContainerNode',
        })
    end
  end

  describe "get_nodes" do
    let(:test_node) do
      array_recursive_ostruct(
        :metadata => {
          :name              => 'test-node',
          :uid               => 'f0c1fe7e-9c09-11e5-bb22-28d2447dcefe',
          :resourceVersion   => '369104',
          :creationTimestamp => '2016-01-01T11:10:21Z'
        },
        :spec     => {
          :providerID => 'aws:///zone/aws-id'
        },
        :status   => {
          :capacity => {}
        }
      )
    end
    let(:test_node1) do
      array_recursive_ostruct(
        :metadata => {
          :name              => 'test-node1',
          :uid               => 'f0c1fe7e-9c09-11e5-bb22-28d2447dcefe',
          :resourceVersion   => '369104',
          :creationTimestamp => '2016-01-01T11:10:21Z'
        },
        :spec     => {
          :providerID => 'aws:///zone/aws-id'
        },
        :status   => {
          :capacity => {}
        }
      )
    end

    pending "handles node with single custom attribute" do
      inventory = {
        "additional_attributes" => { "node/test-node/key" => "val" },
        "node"                  => [test_node]
      }
      parser.get_additional_attributes_graph(inventory)
      parser.get_nodes_graph(inventory)
      expect(parser.instance_variable_get(:@data)[:container_nodes]).to match(
        [
          a_hash_including(
            :name                  => 'test-node',
            :additional_attributes => [{ :name => "key", :value => "val", :section => "additional_attributes" }]
          )
        ]
      )
    end

    pending "handles node with multiple custom attributes" do
      inventory = {
        "additional_attributes" => { "node/test-node/key1" => "val1",
                                     "node/test-node/key2" => "val2"},
        "node"                  => [test_node]
      }
      parser.get_additional_attributes_graph(inventory)
      parser.get_nodes_graph(inventory)
      expect(parser.instance_variable_get(:@data)[:container_nodes]).to match(
        [
          a_hash_including(
            :name                  => 'test-node',
            :additional_attributes => [{ :name => "key1", :value => "val1", :section => "additional_attributes" },
                                       { :name => "key2", :value => "val2", :section => "additional_attributes" }]
          )
        ]
      )
    end

    pending "ignores custom attributes of a different node" do
      inventory = {
        "additional_attributes" => { "node/test-node1/key1" => "val1",
                                     "node/test-node2/key2" => "val2"},
        "node"                  => [test_node1]
      }
      parser.get_additional_attributes_graph(inventory)
      parser.get_nodes_graph(inventory)
      expect(parser.instance_variable_get(:@data)[:container_nodes]).to match(
        [
          a_hash_including(
            :name                  => 'test-node1',
            :additional_attributes => [{ :name => "key1", :value => "val1", :section => "additional_attributes" }]
          )
        ]
      )
    end
  end

  describe "parse_additional_attribute" do
    it "parses node attribute" do
      expect(
        parser.send(
          :parse_additional_attribute,
          %w(node/test-node/key val)
        )
      ).to eq(:node => "test-node", :name => "key", :value => "val", :section => "additional_attributes")
    end
    it "parses pod attribute" do
      expect(
        parser.send(
          :parse_additional_attribute,
          %w(pod/test-pod/key val)
        )
      ).to eq(:pod => "test-pod", :name => "key", :value => "val", :section => "additional_attributes")
    end
    it "parses empty attribute" do
      expect(
        parser.send(
          :parse_additional_attribute,
          []
        )
      ).to eq({})
    end

    it "parses wrong format" do
      expect(
        parser.send(
          :parse_additional_attribute,
          %w(key1 val1)
        )
      ).to eq({})
    end
  end

  describe "parse_persistent_volume" do
    it "tests parent type" do
      expect(parser.send(
        :parse_persistent_volume,
        array_recursive_ostruct(
          :metadata => {
            :name              => 'test-volume',
            :uid               => '66213621-80a1-11e5-b907-28d2447dcefe',
            :resourceVersion   => '448015',
            :creationTimestamp => '2015-12-06T11:10:21Z'
          },
          :spec     => {
            :capacity    => {
              :storage => '10Gi'
            },
            :hostPath    => {
              :path => '/tmp/data01'
            },
            :accessModes => ['ReadWriteOnce'],
          },
          :status   => {
            :phase => 'Available'
          }
        )
      ).data).to include(
        {
          :name                        => 'test-volume',
          :ems_ref                     => '66213621-80a1-11e5-b907-28d2447dcefe',
          :ems_created_on              => '2015-12-06T11:10:21Z',
          :resource_version            => '448015',
          :type                        => 'PersistentVolume',
          :status_phase                => 'Available',
          :access_modes                => 'ReadWriteOnce',
          :capacity                    => {:storage => 10.gigabytes},
          :claim_name                  => nil,
          :common_fs_type              => nil,
          :common_partition            => nil,
          :common_path                 => '/tmp/data01',
          :common_read_only            => nil,
          :common_secret               => nil,
          :common_volume_id            => nil,
          :empty_dir_medium_type       => nil,
          :gce_pd_name                 => nil,
          :git_repository              => nil,
          :git_revision                => nil,
          :glusterfs_endpoint_name     => nil,
          :iscsi_iqn                   => nil,
          :iscsi_lun                   => nil,
          :iscsi_target_portal         => nil,
          :nfs_server                  => nil,
          :rbd_ceph_monitors           => '',
          :rbd_image                   => nil,
          :rbd_keyring                 => nil,
          :rbd_pool                    => nil,
          :rbd_rados_user              => nil,
          :reclaim_policy              => nil,
          :status_message              => nil,
          :status_reason               => nil
        })
    end
  end

  describe "parse_persistent_volume_claim" do
    it "tests pending persistent volume claim" do
      expect(parser.send(
        :parse_persistent_volume_claim,
        array_recursive_ostruct(
          :metadata => {
            :name              => 'test-claim',
            :uid               => '1577c5ba-a3f6-11e5-9845-28d2447dcefe',
            :resourceVersion   => '448015',
            :creationTimestamp => '2015-12-06T11:10:21Z'
          },
          :spec     => {
            :accessModes => ['ReadWriteOnce'],
            :resources   => {
              :requests => {
                :storage => '3Gi'
              },
              :limits   => {
                :storage => '5Gi'
              }
            },
          },
          :status   => {
            :phase => 'Pending',
          }
        )
      ).data).to include(
        {
          :name                 => 'test-claim',
          :ems_ref              => '1577c5ba-a3f6-11e5-9845-28d2447dcefe',
          :ems_created_on       => '2015-12-06T11:10:21Z',
          :namespace            => nil,
          :resource_version     => '448015',
          :desired_access_modes => ['ReadWriteOnce'],
          :requests             => {:storage => 3.gigabytes},
          :limits               => {:storage => 5.gigabytes},
          :phase                => 'Pending',
          :actual_access_modes  => nil,
          :capacity             => {}
        })
    end

    it "tests bounded persistent volume claim" do
      expect(parser.send(
        :parse_persistent_volume_claim,
        array_recursive_ostruct(
          :metadata => {
            :name              => 'test-claim',
            :uid               => '1577c5ba-a3f6-11e5-9845-28d2447dcefe',
            :resourceVersion   => '448015',
            :creationTimestamp => '2015-12-06T11:11:21Z'
          },
          :spec     => {
            :accessModes => %w(ReadWriteOnce ReadWriteMany),
            :resources   => {
              :requests => {
                :storage => '3Gi'
              }
            }
          },
          :status   => {
            :phase       => 'Bound',
            :accessModes => %w(ReadWriteOnce ReadWriteMany),
            :capacity    => {
              :storage => '10Gi'
            }
          }
        )
      ).data).to include(
        {
          :name                 => 'test-claim',
          :ems_ref              => '1577c5ba-a3f6-11e5-9845-28d2447dcefe',
          :ems_created_on       => '2015-12-06T11:11:21Z',
          :namespace            => nil,
          :resource_version     => '448015',
          :desired_access_modes => %w(ReadWriteOnce ReadWriteMany),
          :requests             => {:storage => 3.gigabytes},
          :limits               => {},
          :phase                => 'Bound',
          :actual_access_modes  => %w(ReadWriteOnce ReadWriteMany),
          :capacity             => {:storage => 10.gigabytes}
        })
    end
  end

  context "services" do
    let(:service) do
      array_recursive_ostruct(
        :metadata => {
          :name              => "docker-registry",
          :namespace         => "default",
          :selfLink          => "/api/v1/namespaces/default/services/docker-registry",
          :uid               => "13d3bcf7-e6f9-11e6-a348-001a4a162683",
          :resourceVersion   => "651",
          :creationTimestamp => "2017-01-30T14:33:33Z",
          :labels            => {:"docker-registry" => "default"},
        },
        :spec     => {
          :ports           => [
            {:name => "5000-tcp", :protocol => "TCP", :port => 5000, :targetPort => 5000},
          ],
          :selector        => {:"docker-registry" => "default"},
          :portalIP        => "172.30.185.88",
          :clusterIP       => "172.30.185.88",
          :type            => "ClusterIP",
          :sessionAffinity => "ClientIP",
        },
        :status   => {
          :loadBalancer => {}
        },
      )
    end

    describe "parse_service" do
      it "handles simple data" do
        expect(parser.parse_service(service)).to eq(
          :ems_ref                        => "13d3bcf7-e6f9-11e6-a348-001a4a162683",
          :name                           => "docker-registry",
          :namespace                      => "default",
          :ems_created_on                 => "2017-01-30T14:33:33Z",
          :resource_version               => "651",
          :portal_ip                      => "172.30.185.88",
          :session_affinity               => "ClientIP",
          :service_type                   => "ClusterIP",
          :labels                         => [
            {:section => "labels", :source => "kubernetes", :name => "docker-registry", :value => "default"},
          ],
          :tags                           => [],
          :selector_parts                 => [
            {:section => "selectors", :source => "kubernetes", :name => "docker-registry", :value => "default"},
          ],
          :container_service_port_configs => [
            {:ems_ref => "13d3bcf7-e6f9-11e6-a348-001a4a162683_5000_5000",
             :name => "5000-tcp", :protocol => "TCP", :port => 5000, :target_port => 5000, :node_port => nil},
          ]
        )
      end
    end

    describe "parse_quantity" do
      let(:container_spec) do
        array_recursive_ostruct(
          :name         => "mongodb",
          :image        => "centos/mongodb-32-centos7@sha256:02685168dd84c9119f8ab635078eec8697442fba93a7b342095e03b31aa8c5dd",
          :ports        => [{:containerPort => 27_017, :protocol => "TCP"}],
          :resources    => {
            :limits   => {
              :cpu    => "3500m",
              :memory => "512Mi"
            },
            :requests => {
              #:cpu    => nil
              :memory => "1.2e6"
            }
          },
          :volumeMounts => []
        )
      end

      let(:pod_id) { "95b9aa14-7186-11e7-8ac6-001a4a162683" }

      it "handles parsing of quantities in container spec limits" do
        expect(parser.parse_container_spec(container_spec, pod_id)).to include(
          :limit_cpu_cores      => 3.5,
          :limit_memory_bytes   => 536_870_912,
          :request_cpu_cores    => nil,
          :request_memory_bytes => 1_200_000.0
        )
      end
    end

    describe "parse_capacity_field" do
      let(:node_spec) do
        array_recursive_ostruct(
          :metadata => {
            :name              => "10.35.0.169",
            :uid               => "6de77025-35f0-11e5-8917-001a4a5f4a00",
            :resourceVersion   => "5302",
            :creationTimestamp => "2015-07-29T12:50:45Z",
            :labels            => {
              :"kubernetes.io/hostname" => "10.35.0.169"
            }
          },
          :spec     => {
            :externalID => "10.35.0.169"
          },
          :status   => {
            :capacity => {
              :cpu    => "2",
              :memory => capacity_memory,
              :pods   => "40"
            }
          }
        )
      end

      context "with a Decimal SI value" do
        let(:capacity_memory) { "2M" }

        it "handles parsing of quantities in node spec memory" do
          expected_memory_mb = 2_000_000.0 / 1.megabyte
          parser.parse_node(node_spec)
          expect(persister.computer_system_hardwares.data.first.data).to include(
            :memory_mb => expected_memory_mb
          )
        end
      end

      context "with a IEC 60027-2 value" do
        let(:capacity_memory) { "2Mi" }

        it "handles parsing of quantities in node spec memory" do
          expected_memory_mb = 2.0
          parser.parse_node(node_spec)
          expect(persister.computer_system_hardwares.data.first.data).to include(
            :memory_mb => expected_memory_mb
          )
        end
      end
    end
  end
end
