describe ManageIQ::Providers::Kubernetes::MonitoringManager do
  let(:default_endpoint) { FactoryGirl.create(:endpoint, :role => 'default', :hostname => 'host') }
  let(:default_authentication) { FactoryGirl.create(:authentication, :authtype => 'bearer') }
  let(:prometheus_alerts_endpoint) do
    EvmSpecHelper.local_miq_server(:zone => Zone.seed)
    FactoryGirl.create(
      :endpoint,
      :role       => 'prometheus_alerts',
      :hostname   => 'alerts-prometheus.10.35.48.34.nip.io',
      :port       => 443,
      :verify_ssl => false
    )
  end
  let(:prometheus_authentication) do
    FactoryGirl.create(
      :authentication,
      :authtype => :prometheus_alerts,
      :auth_key => 'eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJtYW5hZ2VtZW50LWluZnJhIiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9zZWNyZXQubmFtZSI6Im1hbmFnZW1lbnQtYWRtaW4tdG9rZW4tMnBzZjMiLCJrdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3NlcnZpY2UtYWNjb3VudC5uYW1lIjoibWFuYWdlbWVudC1hZG1pbiIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50LnVpZCI6IjJiMjg1MmIyLTZjNzAtMTFlNy1hYTlmLTAwMWE0YTE2MjYxOSIsInN1YiI6InN5c3RlbTpzZXJ2aWNlYWNjb3VudDptYW5hZ2VtZW50LWluZnJhOm1hbmFnZW1lbnQtYWRtaW4ifQ.OSh7pgdRXAIUh8hPipfj_me-T3cwI_DsqQUSV1yYo1qvGEd1Aa-oVaBAeKsbwjCDhcNw2nNTWkdeYoy4-MyoTjleZbvdsbtSgs84LCPdLfaVd7NXBiXtNj6o4a2tbcE_GUTBiOEyZfzFh5pwM1n9BbU6qwAvf5B-uiAuGI1VZXyiUWtlspNAEPOy3awFNt9vausNahfMRox9MLB62BYzj2NV36inpNY_UWMNV0X0Q1VnZWO6-v28JAkWhuqaRHgSOUKV1FKJDY6R4rCGxt5BnVS6_81au80vouZmv0oR6kvDPWZo6IVPG8JCIpxK0liJW65pxKIBf7oOkEzhi3wy9w',
    )
  end

  let(:container_manager) do
    FactoryGirl.create(
      :ems_kubernetes,
      :endpoints       => [
        default_endpoint,
        prometheus_alerts_endpoint,
      ],
      :authentications => [
        default_authentication,
        prometheus_authentication,
      ],
    )
  end

  let(:monitoring_manager) { container_manager.monitoring_manager }

  context "#authentication" do
    it "validates authentication with a proper response from message-buffer" do
      VCR.use_cassette(
        described_class.name.underscore,
        # :record => :new_episodes,
      ) do
        expect(monitoring_manager.authentication_status_ok?).to be_falsey
        monitoring_manager.authentication_check_types
        expect(monitoring_manager.authentication_status_ok?).to be_truthy
      end
    end
  end
end
