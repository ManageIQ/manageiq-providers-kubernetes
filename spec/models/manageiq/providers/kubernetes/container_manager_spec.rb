require 'MiqContainerGroup/MiqContainerGroup'

describe ManageIQ::Providers::Kubernetes::ContainerManager do
  it ".ems_type" do
    expect(described_class.ems_type).to eq('kubernetes')
  end

  it ".raw_api_endpoint (ipv6)" do
    expect(described_class.raw_api_endpoint("::1", 123).to_s).to eq "https://[::1]:123"
  end

  describe ".params_for_create" do
    before do
      stub_settings(:http_proxy => {:default => {}}, :ems => {:ems_kubernetes => {}})
    end

    it "dynamically adjusts to new http_proxy value" do
      options = DDF.find_field(described_class.params_for_create, 'options.proxy_settings.http_proxy')
      expect(options[:placeholder]).to be_blank

      stub_settings_merge(:http_proxy => {:default => {:host => "example.com", :port => 1234}})
      options = DDF.find_field(described_class.params_for_create, 'options.proxy_settings.http_proxy')
      expect(options[:placeholder]).to eq "http://example.com:1234"
    end

    it "dynamically adjusts to new image_inspector_repository value" do
      options = DDF.find_field(described_class.params_for_create, 'options.image_inspector_options.repository')
      expect(options[:placeholder]).to be_blank

      stub_settings_merge(:ems => {:ems_kubernetes => {:image_inspector_repository => "http://example.com/repository"}})
      options = DDF.find_field(described_class.params_for_create, 'options.image_inspector_options.repository')
      expect(options[:placeholder]).to eq "http://example.com/repository"
    end

    it "dynamically adjusts to new image_inspector_registry value" do
      options = DDF.find_field(described_class.params_for_create, 'options.image_inspector_options.registry')
      expect(options[:placeholder]).to be_blank

      stub_settings_merge(:ems => {:ems_kubernetes => {:image_inspector_registry => "http://example.com/registry"}})
      options = DDF.find_field(described_class.params_for_create, 'options.image_inspector_options.registry')
      expect(options[:placeholder]).to eq "http://example.com/registry"
    end

    it "dynamically adjusts to new image_inspector_cve_url value" do
      options = DDF.find_field(described_class.params_for_create, 'options.image_inspector_options.cve_url')
      expect(options[:placeholder]).to be_blank

      stub_settings_merge(:ems => {:ems_kubernetes => {:image_inspector_cve_url => "http://example.com/cve_url"}})
      options = DDF.find_field(described_class.params_for_create, 'options.image_inspector_options.cve_url')
      expect(options[:placeholder]).to eq "http://example.com/cve_url"
    end
  end

  describe ".create_from_params" do
    let(:zone)   { EvmSpecHelper.create_guid_miq_server_zone.last }
    let(:params) { {"name" => "k8s", "zone" => zone} }

    context "with a single default endpoint" do
      let(:endpoints) { [{"role" => "default", "hostname" => "kubernetes.local", "port" => 6443, "security_protocol" => "ssl-with-validation"}] }
      let(:authentications) { [{"authtype" => "bearer", "auth_key" => "super secret"}] }

      it "creates the EMS" do
        ems = described_class.create_from_params(params, endpoints, authentications)
        expect(ems.name).to eq(params["name"])
        expect(ems.endpoints.count).to eq(1)
        expect(ems.endpoints.find_by(:role => "default")).to have_attributes(
          :hostname          => "kubernetes.local",
          :port              => 6443,
          :security_protocol => "ssl-with-validation"
        )
        expect(ems.authentications.count).to eq(1)
        expect(ems.authentications.find_by(:authtype => "bearer")).to have_attributes(
          "auth_key" => "super secret"
        )
      end
    end

    context "with a metrics endpoint" do
      let(:endpoints) do
        [
          {"role" => "default",    "hostname" => "kubernetes.local",            "port" => 6443, "security_protocol" => "ssl-with-validation"},
          {"role" => "prometheus", "hostname" => "prometheus.kubernetes.local", "port" => 443,  "security_protocol" => "ssl-with-validation"}
        ]
      end
      let(:authentications) do
        [
          {"authtype" => "bearer", "auth_key" => "super secret"}
        ]
      end

      it "copies the default auth_key to the prometheus endpoint" do
        ems = described_class.create_from_params(params, endpoints, authentications)
        expect(ems.endpoints.count).to eq(2)
        expect(ems.authentications.count).to eq(2)
        expect(ems.authentications.find_by(:authtype => "prometheus")).to have_attributes(
          "auth_key" => "super secret"
        )
      end
    end

    context "with an alerts endpoint" do
      let(:endpoints) do
        [
          {"role" => "default",           "hostname" => "kubernetes.local",                   "port" => 6443, "security_protocol" => "ssl-with-validation"},
          {"role" => "prometheus_alerts", "hostname" => "prometheus_alerts.kubernetes.local", "port" => 443,  "security_protocol" => "ssl-with-validation"}
        ]
      end
      let(:authentications) do
        [
          {"authtype" => "bearer", "auth_key" => "super secret"}
        ]
      end

      it "copies the default auth_key to the prometheus endpoint" do
        ems = described_class.create_from_params(params, endpoints, authentications)
        expect(ems.endpoints.count).to eq(2)
        expect(ems.authentications.count).to eq(2)
        expect(ems.authentications.find_by(:authtype => "prometheus_alerts")).to have_attributes(
          "auth_key" => "super secret"
        )
      end
    end

    context "with a virtualization endpoint" do
      let(:endpoints) do
        [
          {"role" => "default",  "hostname" => "kubernetes.local",          "port" => 6443, "security_protocol" => "ssl-with-validation"},
          {"role" => "kubevirt", "hostname" => "kubevirt.kubernetes.local", "port" => 443,  "security_protocol" => "ssl-with-validation"}
        ]
      end
      let(:authentications) do
        [
          {"authtype" => "bearer",   "auth_key" => "super secret"},
          {"authtype" => "kubevirt", "auth_key" => "also super secret"}
        ]
      end

      it "has a different token from the default auth_key" do
        ems = described_class.create_from_params(params, endpoints, authentications)
        expect(ems.endpoints.count).to eq(2)
        expect(ems.authentications.count).to eq(2)
        expect(ems.authentications.find_by(:authtype => "kubevirt")).to have_attributes(
          "auth_key" => "also super secret"
        )
      end
    end
  end

  describe "#edit_with_params" do
    let!(:ems) do
      FactoryBot.create(:ems_kubernetes_with_zone).tap do |ems|
        ems.authentications << FactoryBot.create(:authentication, "authtype" => "bearer", "auth_key" => "super secret")
      end
    end
    let(:params) { {"name" => ems.name, "zone" => ems.zone} }

    context "without changing the default token" do
      let(:authentications) { [{"authtype" => "bearer"}] }

      context "adding a metrics endpoint" do
        let(:endpoints) { [{"role" => "default", "hostname" => ems.hostname, "port" => ems.port}, {"role" => "prometheus", "hostname" => "prometheus.#{ems.hostname}"}] }

        it "copies the auth_key from the default authentication" do
          ems.edit_with_params(params, endpoints, authentications)
          ems.reload

          expect(ems.authentications.count).to eq(2)
          expect(ems.authentications.find_by(:authtype => "prometheus")).to have_attributes(
            "auth_key" => ems.default_authentication.auth_key
          )
        end
      end

      context "with a metrics endpoint" do
        before do
          ems.endpoints       << FactoryBot.create(:endpoint, :hostname => "prometheus")
          ems.authentications << FactoryBot.create(:authentication, :auth_key => "super secret")
        end

        context "modifying a metrics endpoint" do
          let(:endpoints) { [{"role" => "default", "hostname" => ems.hostname, "port" => ems.port}, {"role" => "prometheus", "hostname" => "prometheus-new"}] }

          it "updates the prometheus hostname" do
            ems.edit_with_params(params, endpoints, authentications)
            ems.reload

            expect(ems.endpoints.find_by(:role => "prometheus")).to have_attributes(
              :hostname => "prometheus-new"
            )
          end

          it "copies the auth_key from the default authentication" do
            ems.edit_with_params(params, endpoints, authentications)
            ems.reload

            expect(ems.authentications.count).to eq(2)
            expect(ems.authentications.find_by(:authtype => "prometheus")).to have_attributes(
              "auth_key" => ems.default_authentication.auth_key
            )
          end
        end

        context "deleting a metrics endpoint" do
          let(:endpoints) { [{"role" => "default", "hostname" => ems.hostname, "port" => ems.port}] }

          it "deletes the metrics endpoint and authention" do
            ems.edit_with_params(params, endpoints, authentications)
            ems.reload

            expect(ems.endpoints.count).to       eq(1)
            expect(ems.authentications.count).to eq(1)
          end
        end
      end
    end

    context "changing the default token" do
      let(:authentications) { [{"authtype" => "bearer", "auth_key" => "more super secret"}] }

      context "adding a metrics endpoint" do
        let(:endpoints) { [{"role" => "default", "hostname" => ems.hostname, "port" => ems.port}, {"role" => "prometheus", "hostname" => "prometheus.#{ems.hostname}"}] }

        it "copies the new auth_key from the params" do
          ems.edit_with_params(params, endpoints, authentications)
          ems.reload

          expect(ems.authentications.count).to eq(2)
          expect(ems.authentications.find_by(:authtype => "prometheus")).to have_attributes(
            "auth_key" => "more super secret"
          )
        end
      end

      context "with a metrics endpoint" do
        before do
          ems.endpoints       << FactoryBot.create(:endpoint, :hostname => "prometheus")
          ems.authentications << FactoryBot.create(:authentication, :auth_key => "super secret")
        end

        context "modifying a metrics endpoint" do
          let(:endpoints) { [{"role" => "default", "hostname" => ems.hostname, "port" => ems.port}, {"role" => "prometheus", "hostname" => "prometheus-new"}] }

          it "updates the prometheus hostname" do
            ems.edit_with_params(params, endpoints, authentications)
            ems.reload

            expect(ems.endpoints.find_by(:role => "prometheus")).to have_attributes(
              :hostname => "prometheus-new"
            )
          end

          it "copies the new auth_key from the params" do
            ems.edit_with_params(params, endpoints, authentications)
            ems.reload

            expect(ems.authentications.count).to eq(2)
            expect(ems.authentications.find_by(:authtype => "prometheus")).to have_attributes(
              "auth_key" => "more super secret"
            )
          end
        end

        context "deleting a metrics endpoint" do
          let(:endpoints) { [{"role" => "default", "hostname" => ems.hostname, "port" => ems.port}, {"role" => "prometheus", "hostname" => "prometheus.#{ems.hostname}"}] }

          it "copies the new auth_key from the params" do
            ems.edit_with_params(params, endpoints, authentications)
            ems.reload

            expect(ems.authentications.count).to eq(2)
            expect(ems.authentications.find_by(:authtype => "prometheus")).to have_attributes(
              "auth_key" => "more super secret"
            )
          end
        end
      end
    end
  end

  describe "hostname_uniqueness_valid?" do
    it "allows duplicate hostname with different ports" do
      FactoryBot.create(:ems_kubernetes, :hostname => "k8s.local", :port => 6443)
      expect { FactoryBot.create(:ems_kubernetes, :hostname => "k8s.local", :port => 443) }.not_to raise_error
    end

    it "rejects a second provider with duplicate hostname and port" do
      FactoryBot.create(:ems_kubernetes, :hostname => "k8s.local", :port => 6443)
      expect { FactoryBot.create(:ems_kubernetes, :hostname => "k8s.local", :port => 6443) }.to raise_error(ActiveRecord::RecordInvalid, /Hostname has to be unique per provider type/)
    end
  end

  context "#supports?(:metrics)" do
    before(:each) do
      EvmSpecHelper.local_miq_server(:zone => Zone.seed)
    end

    it "regular provider has no metrics support" do
      ems = FactoryBot.create(
        :ems_kubernetes,
        :endpoints => [
          Endpoint.new(:role => 'default', :hostname => 'hostname')
        ]
      )

      expect(ems.supports?(:metrics)).to be_falsey
    end

    it "provider with prometheus endpoint has metrics support" do
      ems = FactoryBot.create(
        :ems_kubernetes,
        :endpoints => [
          Endpoint.new(:role => 'default', :hostname => 'hostname'),
          Endpoint.new(:role => 'prometheus')
        ]
      )

      expect(ems.supports?(:metrics)).to be_truthy
    end

    it "provider with some role endpoint has no metrics support" do
      ems = FactoryBot.create(
        :ems_kubernetes,
        :endpoints => [
          Endpoint.new(:role => 'default', :hostname => 'hostname'),
          Endpoint.new(:role => 'some_role')
        ]
      )

      expect(ems.supports?(:metrics)).to be_falsey
    end
  end

  context "#verify_ssl_mode" do
    let(:ems) { FactoryBot.build(:ems_kubernetes) }

    it "is secure without endpoint" do
      expect(ems.verify_ssl_mode(nil)).to eq(OpenSSL::SSL::VERIFY_PEER)
    end

    it "is secure for old providers without security_protocol" do
      endpoint = Endpoint.new(:verify_ssl => nil)
      expect(ems.verify_ssl_mode(endpoint)).to eq(OpenSSL::SSL::VERIFY_PEER)
      # In practice both API and UI used set verify_ssl == VERIFY_PEER.
      endpoint = Endpoint.new(:verify_ssl => OpenSSL::SSL::VERIFY_PEER)
      expect(ems.verify_ssl_mode(endpoint)).to eq(OpenSSL::SSL::VERIFY_PEER)
    end

    it "respects explicit verify_ssl == 0 in absence of security_protocol" do
      endpoint = Endpoint.new(:verify_ssl => OpenSSL::SSL::VERIFY_NONE)
      expect(endpoint.verify_ssl?).to be_falsey
      expect(ems.verify_ssl_mode(endpoint)).to eq(OpenSSL::SSL::VERIFY_NONE)
    end

    it "uses security_protocol when given" do
      # security_protocol should win over opposite verify_ssl
      endpoint = Endpoint.new(:security_protocol => 'ssl-with-validation',
                              :verify_ssl        => OpenSSL::SSL::VERIFY_NONE)
      expect(ems.verify_ssl_mode(endpoint)).to eq(OpenSSL::SSL::VERIFY_PEER)

      # The UI doesn't currently use 'ssl' but it's plausible someone
      # would send this via API.  Generally unexpect values should mean secure.
      endpoint = Endpoint.new(:security_protocol => 'ssl',
                              :verify_ssl        => OpenSSL::SSL::VERIFY_NONE)
      expect(ems.verify_ssl_mode(endpoint)).to eq(OpenSSL::SSL::VERIFY_PEER)

      endpoint = Endpoint.new(:security_protocol => 'ssl-with-validation-custom-ca',
                              :verify_ssl        => OpenSSL::SSL::VERIFY_NONE)
      expect(ems.verify_ssl_mode(endpoint)).to eq(OpenSSL::SSL::VERIFY_PEER)

      endpoint = Endpoint.new(:security_protocol => 'ssl-without-validation',
                              :verify_ssl        => OpenSSL::SSL::VERIFY_PEER)
      expect(ems.verify_ssl_mode(endpoint)).to eq(OpenSSL::SSL::VERIFY_NONE)
    end
  end

  context "SmartState Analysis Methods" do
    before(:each) do
      EvmSpecHelper.local_miq_server(:zone => Zone.seed)
      @ems = FactoryBot.create(
        :ems_kubernetes,
        :hostname        => 'hostname',
        :authentications => [
          FactoryBot.build(:authentication, :authtype => 'bearer', :auth_key => 'valid-token'),
          FactoryBot.build(:authentication, :authtype => 'prometheus')
        ]
      )
      allow(@ems).to receive_message_chain(:connect, :proxy_url => "Hello")
      allow(@ems).to receive_message_chain(:connect, :headers   => { "Authorization" => "Bearer valid-token" })
    end

    it "checks for the right credential fields" do
      expect(@ems.required_credential_fields(:bearer)).to eq([:auth_key])
    end

    it "checks for missing_credentials" do
      expect(@ems.missing_credentials?(:bearer)).to be_falsey
      expect(@ems.missing_credentials?(:prometheus)).to be_truthy
    end

    it ".scan_entity_create" do
      entity = @ems.scan_entity_create(
        :pod_namespace => 'default',
        :pod_name      => 'name',
        :pod_port      => 8080,
        :guest_os      => 'GuestOS'
      )

      expect(entity).to be_kind_of(MiqContainerGroup)
      expect(entity.http_options).to include(:use_ssl => true, :verify_mode => @ems.verify_ssl_mode)
      expect(entity.headers).to eq("Authorization" => "Bearer valid-token")
      expect(entity.guest_os).to eq('GuestOS')
    end

    it ".scan_job_create" do
      image = FactoryBot.create(:container_image, :ext_management_system => @ems)
      User.current_user = FactoryBot.create(:user, :userid => "bob")
      job = @ems.raw_scan_job_create(image.class, image.id, User.current_user.userid)

      expect(job.state).to eq("waiting_to_start")
      expect(job.status).to eq("ok")
      expect(job.target_class).to eq(image.class.name)
      expect(job.target_id).to eq(image.id)
      expect(job.type).to eq(ManageIQ::Providers::Kubernetes::ContainerManager::Scanning::Job.name)
      expect(job.zone).to eq(@ems.zone.name)
      expect(job.userid).to eq("bob")
    end
  end

  context "kubeclient" do
    let(:hostname) { "hostname" }
    let(:port) { "1234" }
    let(:options) { { :ssl_options => { :bearer_token => "4321" } } }
    it ". raw_connect" do
      uri = URI::HTTP.build(:host => "some")
      allow(VMDB::Util).to receive(:http_proxy_uri).and_return(uri)

      require 'kubeclient'

      client = Kubeclient::Client.new(uri)
      expect(client).to receive(:discover)

      expect(Kubeclient::Client).to receive(:new).with(
        instance_of(URI::HTTPS), 'v1',
        hash_including(:http_proxy_uri => VMDB::Util.http_proxy_uri,
                       :timeouts       => match(:open => be > 0, :read => be > 0))
      ).and_return(client)

      described_class.raw_connect(hostname, port, options)
    end

    it "connect uses provider options for http_proxy" do
      uri = URI::HTTP.build(:host => "some")
      allow(VMDB::Util).to receive(:http_proxy_uri).and_return(uri)

      require 'kubeclient'
      my_proxy_value = "internal_proxy.org"

      client = Kubeclient::Client.new(uri)
      expect(client).to receive(:discover)

      expect(Kubeclient::Client).to receive(:new).with(
        instance_of(URI::HTTPS), 'v1',
        hash_including(:http_proxy_uri => my_proxy_value)
      ).and_return(client)

      ems = FactoryBot.create(
        :ems_kubernetes,
        :endpoints => [
          FactoryBot.create(:endpoint, :role => 'default', :hostname => 'host'),
          FactoryBot.create(:endpoint, :role => 'prometheus_alerts', :hostname => 'host2'),
        ]
      )
      ems.update(:options => {:proxy_settings => {:http_proxy => my_proxy_value}})
      ems.connect
    end
  end

  # Test MonitoringManager functionality related to ContainerManager
  context "MonitoringManager" do
    it "Creates a monitoring manager when container manager is created with a prometheus_alert endpoint" do
      ems = FactoryBot.create(
        :ems_kubernetes,
        :endpoints => [
          FactoryBot.build(:endpoint, :role => 'default', :hostname => 'host'),
          FactoryBot.build(:endpoint, :role => 'prometheus_alerts', :hostname => 'host2'),
        ]
      )
      expect(ems.monitoring_manager).not_to be_nil
      expect(ems.monitoring_manager.parent_manager).to eq(ems)
    end

    it "Does not create a monitoring manager when there is no prometheus_alert endpoint" do
      ems = FactoryBot.create(
        :ems_kubernetes,
        :endpoints => [
          FactoryBot.create(:endpoint, :role => 'default', :hostname => 'host2'),
          FactoryBot.create(:endpoint, :role => 'prometheus', :hostname => 'host2'),
        ]
      )
      expect(ems.monitoring_manager).to be_nil
    end

    it "Creates a monitoring manager when container manager is updated with a prometheus_alerts endpoint" do
      ems = FactoryBot.create(:ems_kubernetes)
      ems.endpoints << FactoryBot.create(:endpoint, :role => 'prometheus_alerts', :hostname => 'host2', :resource => ems)

      expect(ems.monitoring_manager).not_to be_nil
      expect(ems.monitoring_manager.parent_manager).to eq(ems)
    end

    it "Does not create a monitoring manager when added a non prometheus_alerts endpoint" do
      ems = FactoryBot.create(:ems_kubernetes)
      ems.endpoints << FactoryBot.create(:endpoint, :role => 'prometheus', :hostname => 'host2')
      expect(ems.monitoring_manager).to be_nil
    end

    it "Deletes the monitoring manager when container manager is removed the prometheus_alerts endpoint" do
      ems = FactoryBot.create(
        :ems_kubernetes_with_zone,
        :endpoints => [
          FactoryBot.build(:endpoint, :role => 'default', :hostname => 'host2'),
          FactoryBot.build(:endpoint, :role => 'prometheus_alerts', :hostname => 'host2')
        ]
      )
      expect(ems.monitoring_manager).not_to be_nil
      expect(ems.monitoring_manager.parent_manager).to eq(ems)

      ems.endpoints = [FactoryBot.build(:endpoint, :role => 'default', :hostname => 'host3')]
      queue_item = MiqQueue.find_by(:method_name => 'orchestrate_destroy')
      expect(queue_item).not_to be_nil
      expect(queue_item.instance_id).to eq(ems.monitoring_manager.id)
    end
  end

  context "VirtualizationManager" do
    it "Creates a virtualization manager when container manager is created with kubevirt endpoint" do
      ems = FactoryBot.create(
        :ems_kubernetes,
        :endpoints       => [
          FactoryBot.build(:endpoint, :role => 'default', :hostname => 'host'),
          FactoryBot.build(:endpoint, :role => 'kubevirt', :hostname => 'host'),
        ],
        :authentications => [
          FactoryBot.create(:authentication, :authtype => 'default'),
          FactoryBot.create(:authentication, :authtype => 'kubevirt'),
        ]
      )

      expect(ems.infra_manager).not_to be_nil
      expect(ems.infra_manager.parent_manager).to eq(ems)
      expect(ems.infra_manager.endpoints).not_to be_nil
      expect(ems.infra_manager.authentications).not_to be_nil
      expect(ems.infra_manager.has_authentication_type?(:kubevirt)).to be true
    end

    it "Does not create a virtualization manager when there is no kubevirt endpoint" do
      ems = FactoryBot.create(
        :ems_kubernetes,
        :endpoints => [
          FactoryBot.build(:endpoint, :role => 'default', :hostname => 'host'),
          FactoryBot.build(:endpoint, :role => 'prometheus', :hostname => 'host2'),
        ]
      )
      expect(ems.infra_manager).to be_nil
    end

    it "Creates a virtualization manager when container manager is updated with a kubevirt endpoint" do
      ems = FactoryBot.create(
        :ems_kubernetes,
        :endpoints => [
          FactoryBot.build(:endpoint, :role => 'default', :hostname => 'host'),
        ]
      )

      ems.endpoints << FactoryBot.build(:endpoint, :role => 'kubevirt', :hostname => 'host')

      expect(ems.infra_manager).not_to be_nil
      expect(ems.infra_manager.parent_manager).to eq(ems)
      expect(ems.infra_manager.endpoints.where(:role => "kubevirt").count).to eq(1)
    end

    it "Does not create a virtualization manager when added a non kubevirt endpoint" do
      ems = FactoryBot.create(:ems_kubernetes)
      ems.endpoints << FactoryBot.create(:endpoint, :role => 'prometheus', :hostname => 'host2')
      expect(ems.infra_manager).to be_nil
    end

    it "Deletes the virtualization manager when container manager is removed the kubevirt endpoint" do
      ems = FactoryBot.create(
        :ems_kubernetes_with_zone,
        :endpoints => [
          FactoryBot.build(:endpoint, :role => 'default', :hostname => 'host'),
          FactoryBot.build(:endpoint, :role => 'kubevirt', :hostname => 'host')
        ]
      )
      expect(ems.infra_manager).not_to be_nil
      expect(ems.infra_manager.parent_manager).to eq(ems)

      ems.endpoints = [FactoryBot.build(:endpoint, :role => 'default', :hostname => 'host')]
      queue_item = MiqQueue.find_by(:method_name => 'orchestrate_destroy')
      expect(queue_item).not_to be_nil
      expect(queue_item.instance_id).to eq(ems.infra_manager.id)
    end
  end
end
