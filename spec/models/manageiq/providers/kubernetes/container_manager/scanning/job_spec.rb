require 'MiqContainerGroup/MiqContainerGroup'

class MockKubeClient
  include ArrayRecursiveOpenStruct

  def create_pod(*_args)
    nil
  end

  def proxy_url(*_args)
    'https://test.com'
  end

  def headers(*_args)
    []
  end

  def get_pod(*_args)
    array_recursive_ostruct(
      :metadata => {
        :annotations => {
          'manageiq.org/jobid' => '5'
        }
      },
      :status   => {
        :containerStatuses => [
          { :ready => true },
        ]
      }
    )
  end

  def get_service_account(*_args)
    array_recursive_ostruct(
      :metadata         => {
        :name => 'inspector-admin'
      },
      :imagePullSecrets => [
        { :name => 'inspector-admin-dockercfg-blabla' }
      ]
    )
  end

  def ssl_options(*_args)
    {}
  end

  def auth_options(*_args)
    {}
  end
end

class MockKubeClientTwoPullSecrets < MockKubeClient
  def get_service_account(*_args)
    array_recursive_ostruct(
      :metadata         => {
        :name => 'inspector-admin'
      },
      :imagePullSecrets => [
        { :name => 'inspector-admin-dockercfg-blabla' },
        { :name => 'some-other-secret' }
      ]
    )
  end
end

class MockKubeClientPullSecretWOName < MockKubeClient
  def get_service_account(*_args)
    array_recursive_ostruct(
      :metadata         => {
        :name => 'inspector-admin'
      },
      :imagePullSecrets => [
        { :name     => 'inspector-admin-dockercfg-blabla' },
        { :not_name => 'some-other-secret' }
      ]
    )
  end
end

class MockImageInspectorClient
  def initialize(for_id, repo_digest = nil)
    @for_id = for_id
    @repo_digest = repo_digest
  end

  def fetch_metadata(*_args)
    meta = if @repo_digest
             OpenStruct.new('Id' => @for_id, 'RepoDigests' => ["123456677899987765543322", @repo_digest])
           else
             OpenStruct.new('Id' => @for_id)
           end
    meta["OpenSCAP"] = OpenStruct.new("Status" => @status)
    meta
  end

  def fetch_oscap_arf
    File.read(
      File.expand_path(File.join(File.dirname(__FILE__), "ssg-fedora-ds-arf.xml"))
    ).encode("UTF-8")
  end
end

class MockFailedImageInspectorClient < MockImageInspectorClient
  def initialize(status, msg, *args)
    super(*args)
    @status = status
    @msg = msg
  end

  def fetch_metadata(*_args)
    os = super
    os["OpenSCAP"] = OpenStruct.new("Status"       => @status,
                                    "ErrorMessage" => @msg)
    os
  end

  def fetch_oscap_arf
    raise ImageInspectorClient::InspectorClientException.new(404, "test error message")
  end
end

describe ManageIQ::Providers::Kubernetes::ContainerManager::Scanning::Job do
  context "SmartState Analysis Methods" do
    before(:each) do
      EvmSpecHelper.create_guid_miq_server_zone
      @ems = FactoryGirl.create(:ems_kubernetes, :hostname => 'hostname')
    end

    context "#initialize" do
      it "Creates a new scan job" do
        image = FactoryGirl.create(:container_image, :ext_management_system => @ems)
        job = @ems.raw_scan_job_create(image.class, image.id, "bob")
        expect(job).to have_attributes(
          :dispatch_status => "pending",
          :state           => "waiting_to_start",
          :status          => "ok",
          :message         => "process initiated",
          :target_class    => "ContainerImage",
          :userid          => "bob"
        )
      end

      it "It should raise an error when creating a job with instance of Container Image" do
        image = FactoryGirl.create(:container_image, :ext_management_system => @ems)
        User.current_user = FactoryGirl.create(:user, :userid => "bob")
        expect { @ems.raw_scan_job_create(image) }
          .to raise_error(MiqException::Error, "target_class must be a class not an instance")
      end

      it "Is backward compatible with #54" do
        # https://github.com/ManageIQ/manageiq-providers-kubernetes/pull/54/files
        image = FactoryGirl.create(:container_image, :ext_management_system => @ems)
        User.current_user = FactoryGirl.create(:user, :userid => "bob")
        job = @ems.raw_scan_job_create(image.class, image.id, User.current_user.userid)
        expect(job).to have_attributes(
          :dispatch_status => "pending",
          :state           => "waiting_to_start",
          :status          => "ok",
          :message         => "process initiated",
          :target_class    => "ContainerImage",
          :userid          => "bob"
        )
      end
    end
  end

  context "A single Container Scan Job," do
    IMAGE_ID = '3629a651e6c11d7435937bdf41da11cf87863c03f2587fa788cf5cbfe8a11b9a'.freeze
    IMAGE_NAME = 'test'.freeze
    before(:each) do
      @server = EvmSpecHelper.local_miq_server

      allow_any_instance_of(described_class).to receive_messages(:kubernetes_client => MockKubeClient.new)
      allow_any_instance_of(described_class).to receive_messages(
        :image_inspector_client => MockImageInspectorClient.new(IMAGE_ID))

      @ems = FactoryGirl.create(
        :ems_kubernetes, :hostname => "test.com", :zone => @server.zone, :port => 8443,
        :authentications => [AuthToken.new(:name => "test", :type => 'AuthToken', :auth_key => "a secret")]
      )

      @image = FactoryGirl.create(
        :container_image, :ext_management_system => @ems, :name => IMAGE_NAME,
        :image_ref => "docker://#{IMAGE_ID}"
      )

      allow_any_instance_of(@image.class).to receive(:scan_metadata) do |_instance, _args|
        @job.signal(:data, '<summary><scanmetadata></scanmetadata></summary>')
      end

      allow_any_instance_of(@image.class).to receive(:sync_metadata) do |_instance, _args|
        @job.signal(:data, '<summary><syncmetadata></syncmetadata></summary>')
      end

      User.current_user = FactoryGirl.create(:user)
      @job = @ems.raw_scan_job_create(@image.class, @image.id)
      allow(MiqQueue).to receive(:put_unless_exists) do |args|
        @job.signal(*args[:args])
      end
    end

    context "completes successfully" do
      before(:each) do
        allow_any_instance_of(described_class).to receive_messages(:collect_compliance_data) unless OpenscapResult.openscap_available?

        expect(@job.state).to eq 'waiting_to_start'
        @job.signal(:start)
      end

      it 'should report success' do
        expect(@job.state).to eq 'finished'
        expect(@job.status).to eq 'ok'
      end

      it 'should persist openscap data' do
        skip unless OpenscapResult.openscap_available?

        expect(@image.openscap_result).to be
        expect(@image.openscap_result.binary_blob.md5).to eq('d1f1857281573cd777b31d76e8529dc9')
        expect(@image.openscap_result.openscap_rule_results.count).to eq(213)
      end
    end

    context "when timeout occures during pod_wait state" do
      it "should clean all signals and not fail in the state machine" do
        initial_q_size = MiqQueue.all.count
        MiqQueue.put(**@job.send(:queue_options), :args => [:pod_wait,])
        expect(MiqQueue.all.count).to eq(initial_q_size + 1)
        @job.cancel
        expect(MiqQueue.all.count).to eq(initial_q_size)
      end
    end

    context "#current_job_timeout" do
      it "checks for timeout in Settings" do
        stub_settings_merge(:container_scanning => {:scanning_job_timeout => '15.minutes'})
        expect(@job.send(:current_job_timeout)).to eq(900)
        stub_settings_merge(:container_scanning => {:scanning_job_timeout => 600})
        expect(@job.send(:current_job_timeout)).to eq(600)
      end
    end

    context "using provider options and settings" do
      def create_pod_definition
        allow_any_instance_of(described_class).to receive_messages(:kubernetes_client => MockKubeClient.new)
        kc = @job.kubernetes_client
        secret_name = @job.send(:inspector_admin_secrets)
        @job.send(:pod_definition, secret_name)
      end

      it 'should add correct environment variables from options' do
        att_name = 'http_proxy'
        my_value = "MY_TEST_VALUE"
        @ems.update(:options => { :image_inspector_options => {att_name.to_sym => my_value} })
        pod = create_pod_definition
        expect(pod[:spec][:containers][0][:env][0][:name]).to eq(att_name.upcase)
        expect(pod[:spec][:containers][0][:env][0][:value]).to eq(my_value)
      end

      it 'should send cve_url from options over global' do
        stub_settings_merge(:ems => {:ems_kubernetes => {:image_inspector_cve_url => "from_global" }})
        cve_url_value = "get_cve_from_here.com"
        @ems.update(:options => { :image_inspector_options => {:cve_url => cve_url_value} })
        pod = create_pod_definition
        expect(pod[:spec][:containers][0][:command]
          .select { |cmd| cmd.starts_with?("--cve-url=") }.first.split('=').last).to eq(cve_url_value)
      end

      it 'wont send any cve_url if none is defined' do
        stub_settings_merge(:ems => {:ems_kubernetes => {:image_inspector_cve_url => "" }})
        pod = create_pod_definition
        expect(pod[:spec][:containers][0][:command]
          .select { |cmd| cmd.starts_with?("--cve-url=") }.count).to eq(0)
      end

      it 'should use image_tag option' do
        image_tag = "3.3"
        @ems.update(:options => { :image_inspector_options => {:image_tag => image_tag} })
        pod = create_pod_definition
        expect(pod[:spec][:containers][0][:image].split(':').last).to eq(image_tag)
      end

      it 'uses global defaults for registry,repo,tag and cve_url' do
        stub_settings_merge(
          :ems => {
            :ems_kubernetes => {
              :image_inspector_registry   => "registry1",
              :image_inspector_repository => "repository1",
              :image_inspector_cve_url    => "cve_url1"
            }
          }
        )
        pod = create_pod_definition
        expect(pod[:spec][:containers][0][:command]
          .select { |cmd| cmd.starts_with?("--cve-url=") }.first.split('=').last).to eq("cve_url1")
        expect(pod[:spec][:containers][0][:image]).to eq("registry1/repository1:2.1")
      end
    end

    it 'should send correct dockercfg secrets' do
      allow(@job).to receive(:kubernetes_client).and_return(MockKubeClient.new)
      kc = @job.kubernetes_client
      secret_names = @job.send(:inspector_admin_secrets)
      pod = @job.send(:pod_definition, secret_names)
      secret_name = secret_names.first
      expect(pod[:spec][:containers][0][:command]).to include(
        "--dockercfg=" + described_class::INSPECTOR_ADMIN_SECRET_PATH + secret_name + "/.dockercfg")
      expect(pod[:spec][:containers][0][:volumeMounts]).to include(
        Kubeclient::Resource.new(
          :name      => "inspector-admin-secret-" + secret_name,
          :mountPath => described_class::INSPECTOR_ADMIN_SECRET_PATH + secret_name,
          :readOnly  => true))
      expect(pod[:spec][:volumes]).to include(
        Kubeclient::Resource.new(
          :name   => "inspector-admin-secret-" + secret_name,
          :secret => {:secretName => secret_name}))
    end

    context 'multiple pull secrets' do
      describe '#inspector_admin_secrets' do
        it 'returns a list with one secret name for one secret with name' do
          allow(@job).to receive(:kubernetes_client).and_return(MockKubeClient.new)
          secrets = @job.send(:inspector_admin_secrets)
          expect(secrets.length).to eq(1)
        end

        it 'returns a list with a secret name for each secret' do
          allow(@job).to receive(:kubernetes_client).and_return(MockKubeClientTwoPullSecrets.new)
          secrets = @job.send(:inspector_admin_secrets)
          expect(secrets.length).to eq(2)
          expect(secrets).to contain_exactly('inspector-admin-dockercfg-blabla', 'some-other-secret')
        end

        it 'does not include secrets without a name' do
          allow(@job).to receive(:kubernetes_client).and_return(MockKubeClientPullSecretWOName.new)
          secrets = @job.send(:inspector_admin_secrets)
          expect(secrets.length).to eq(1)
        end
      end

      describe '#pod_definition' do
        it 'will create the pod with multiple dockercfg and secrets' do
          allow(@job).to receive(:kubernetes_client).and_return(MockKubeClientTwoPullSecrets.new)
          secrets = @job.send(:inspector_admin_secrets)
          pod = @job.send(:pod_definition, secrets)
          secrets.each do |secret_name|
            expect(pod[:spec][:containers][0][:command]).to include(
              "--dockercfg=" + described_class::INSPECTOR_ADMIN_SECRET_PATH + secret_name + "/.dockercfg")
            expect(pod[:spec][:containers][0][:volumeMounts]).to include(
              Kubeclient::Resource.new(
                :name      => "inspector-admin-secret-" + secret_name,
                :mountPath => described_class::INSPECTOR_ADMIN_SECRET_PATH + secret_name,
                :readOnly  => true))
            expect(pod[:spec][:volumes]).to include(
              Kubeclient::Resource.new(
                :name   => "inspector-admin-secret-" + secret_name,
                :secret => {:secretName => secret_name}))
          end
        end
      end
    end

    context 'when the job is called with a non existing image' do
      before(:each) do
        @image.delete
      end

      it 'should report the error' do
        @job.signal(:start)
        expect(@job.state).to eq 'finished'
        expect(@job.status).to eq 'error'
        expect(@job.message).to eq "no image found"
      end
    end

    context 'when create pod throws exception' do
      before(:each) do
        allow_any_instance_of(MockKubeClient).to receive(:create_pod) do |_instance, *_args|
          raise KubeException.new(0, 'error', nil)
        end
      end

      it 'should report the error' do
        @job.signal(:start)
        expect(@job.state).to eq 'finished'
        expect(@job.status).to eq 'error'
        expect(@job.message).to eq "pod creation for [management-infra/manageiq-img-scan-#{@job.guid[0..4]}] failed"
      end
    end

    context 'when getting the service account throws exception' do
      before(:each) do
        allow_any_instance_of(MockKubeClient).to receive(:get_service_account) do |_instance, *_args|
          raise KubeException.new(0, 'error', nil)
        end
      end

      it 'should report the error' do
        @job.signal(:start)
        expect(@job.state).to eq 'finished'
        expect(@job.status).to eq 'error'
        expect(@job.message).to eq "getting inspector-admin secret failed"
      end
    end

    context 'when given a non docker image' do
      before(:each) do
        allow_any_instance_of(@image.class).to receive(:image_ref) do
          'rocket://3629a651e6c11d7435937bdf41da11cf87863c03f2587fa788cf5cbfe8a11b9a'
        end
      end

      it 'should fail' do
        @job.signal(:start)
        expect(@job.state).to eq 'finished'
        expect(@job.status).to eq 'error'
        expect(@job.message).to eq "cannot analyze non docker images"
      end
    end

    context 'when the image tag points to a different image' do
      MODIFIED_IMAGE_ID = '0d071bb732e1e3eb1e01629600c9b6c23f2b26b863b5321335f564c8f018c452'.freeze
      before(:each) do
        allow_any_instance_of(described_class).to receive_messages(
          :image_inspector_client => MockImageInspectorClient.new(MODIFIED_IMAGE_ID))
      end

      it 'should check for repo_digests' do
        allow_any_instance_of(described_class).to receive_messages(:collect_compliance_data) unless OpenscapResult.openscap_available?
        allow_any_instance_of(described_class).to receive_messages(
          :image_inspector_client => MockImageInspectorClient.new(MODIFIED_IMAGE_ID, IMAGE_ID))
        @job.signal(:start)
        expect(@job.state).to eq 'finished'
        expect(@job.status).to eq 'ok'
      end

      it 'should report the error' do
        @job.signal(:start)
        expect(@job.state).to eq 'finished'
        expect(@job.status).to eq 'error'
        expect(@job.message).to eq "cannot analyze image #{IMAGE_NAME} with id #{IMAGE_ID[0..11]}:"\
                                   " detected ids were #{MODIFIED_IMAGE_ID[0..11]}"
      end
    end

    context 'reading openscap messages' do
      OSCAP_ERROR_MSG = 'Unable to run OpenSCAP: Unable to get RHEL dist number'.freeze
      OSCAP_SUCCESS_MSG = 'image analysis completed successfully'.freeze

      before(:each) do
        # Expecting to raise from MockFailedImageInspectorClient before getting to use openscap binary
        allow(OpenscapResult).to receive_messages(:openscap_available? => true)
      end

      it 'set the ok status from image-inspector OSCAP' do
        allow_any_instance_of(described_class).to receive_messages(
          :image_inspector_client => MockFailedImageInspectorClient.new("Success", "", IMAGE_ID)
        )
        @job.signal(:start)
        expect(@job.state).to eq 'finished'
        expect(@job.status).to eq 'ok'
        expect(@job.message).to eq OSCAP_SUCCESS_MSG
        expect(@image.last_scan_result.scan_result_message).to eq OSCAP_SUCCESS_MSG
      end

      it 'set the warn status from image-inspector OSCAP' do
        allow_any_instance_of(described_class).to receive_messages(
          :image_inspector_client => MockFailedImageInspectorClient.new("Error", OSCAP_ERROR_MSG, IMAGE_ID)
        )
        @job.signal(:start)
        expect(@job.state).to eq 'finished'
        expect(@job.status).to eq 'warn'
        expect(@job.message).to eq OSCAP_ERROR_MSG
        expect(@image.last_scan_result.scan_result_message).to eq OSCAP_ERROR_MSG
      end
    end

    context '#verify_scanned_image_id' do
      DOCKER_DAEMON_IMAGE_ID = '123456'.freeze

      before(:each) do
        @job.options[:docker_image_id] = IMAGE_ID
        @job.options[:image_full_name] = IMAGE_NAME
      end

      it 'should report the error when the scanned Id is different than the Image Id' do
        msg = @job.verify_scanned_image_id(OpenStruct.new(:Id => DOCKER_DAEMON_IMAGE_ID))
        expect(msg).to eq "cannot analyze image #{IMAGE_NAME} with id #{IMAGE_ID[0..11]}:"\
                          " detected ids were #{DOCKER_DAEMON_IMAGE_ID[0..11]}"
      end

      context 'checking RepoDigests' do
        DOCKER_IMAGE_ID = "image_name@sha256:digest654321abcdef".freeze
        OTHER_REPOD = "OTHER_REPOD".freeze

        before(:each) do
          @job.options[:docker_image_id] = DOCKER_IMAGE_ID
          @job.options[:image_full_name] = "docker-pullable://" + DOCKER_IMAGE_ID
        end

        it 'checks that the Id is in RepoDigests' do
          msg = @job.verify_scanned_image_id(OpenStruct.new(:Id          => DOCKER_DAEMON_IMAGE_ID,
                                                            :RepoDigests => [DOCKER_IMAGE_ID],
                                                           ))
          expect(msg).to eq nil
        end

        it 'checks all the RepoDigests' do
          msg = @job.verify_scanned_image_id(OpenStruct.new(:Id          => DOCKER_DAEMON_IMAGE_ID,
                                                            :RepoDigests => [OTHER_REPOD, DOCKER_IMAGE_ID],
                                                           ))
          expect(msg).to eq nil
        end

        it 'compares RepoDigests hash part only' do
          # in case the image didn't have a defined registry
          msg = @job.verify_scanned_image_id(OpenStruct.new(:Id          => DOCKER_DAEMON_IMAGE_ID,
                                                            :RepoDigests => ["reponame/" + DOCKER_IMAGE_ID],
                                                           ))
          expect(msg).to eq nil
        end

        it 'reports all attempted IDs' do
          # in case the image didn't have a defined registry
          msg = @job.verify_scanned_image_id(OpenStruct.new(:Id          => DOCKER_DAEMON_IMAGE_ID,
                                                            :RepoDigests => [OTHER_REPOD],
                                                           ))
          expect(msg).to eq "cannot analyze image docker-pullable://#{DOCKER_IMAGE_ID} with id #{DOCKER_IMAGE_ID[0..11]}:"\
                            " detected ids were #{DOCKER_DAEMON_IMAGE_ID[0..11]}, #{OTHER_REPOD}"
        end
      end
    end
  end
end
