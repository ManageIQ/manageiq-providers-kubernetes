describe ManageIQ::Providers::Kubernetes::MonitoringManager do
  let(:default_endpoint) { FactoryGirl.create(:endpoint, :role => 'default', :hostname => 'host') }
  let(:default_authentication) { FactoryGirl.create(:authentication, :authtype => 'bearer') }
  let(:prometheus_authentication) do
    FactoryGirl.create(
      :authentication,
      :authtype => 'prometheus_alerts',
      :auth_key => '_',
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

  context "#authentication - no ssl" do
    let(:prometheus_alerts_endpoint) do
      EvmSpecHelper.local_miq_server(:zone => Zone.seed)
      FactoryGirl.create(
        :endpoint,
        :role       => 'prometheus_alerts',
        :hostname   => 'alerts-prometheus.example.com',
        :port       => 443,
        :verify_ssl => false
      )
    end

    it "validates authentication with a proper response from prometheus-alert-buffer" do
      VCR.use_cassette(
        described_class.name.underscore,
        # :record => :new_episodes,
      ) do
        expect(monitoring_manager.authentication_status_ok?).to be_falsey
        container_manager.authentication_check_types
        monitoring_manager.reload
        expect(monitoring_manager.authentication_status_ok?).to be_truthy
      end
    end
  end

  context "#authentication - custom ssl" do
    let(:prometheus_alerts_endpoint) do
      EvmSpecHelper.local_miq_server(:zone => Zone.seed)
      FactoryGirl.create(
        :endpoint,
        :role                  => 'prometheus_alerts',
        :hostname              => 'alerts-prometheus.example.com',
        :port                  => 443,
        :verify_ssl            => true,
        :certificate_authority => certificate_authority
      )
    end
    let(:certificate_authority) do
      <<-EOPEM.strip_heredoc
        -----BEGIN CERTIFICATE-----
        MIIC6jCCAdKgAwIBAgIBATANBgkqhkiG9w0BAQsFADAmMSQwIgYDVQQDDBtvcGVu
        c2hpZnQtc2lnbmVyQDE1MTIwNTMwMDEwHhcNMTcxMTMwMTQ0MzIxWhcNMjIxMTI5
        MTQ0MzIyWjAmMSQwIgYDVQQDDBtvcGVuc2hpZnQtc2lnbmVyQDE1MTIwNTMwMDEw
        ggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCxV3bpJspaWcEYk2cXTrw2
        KhX1LK08kACxkqabPWwzS5xVT+IEdt6xx6rss+5QbFUGd3oxPHOjFNOTCMDADbiW
        OtFDcsfjdkbZI8MEIYAXXQu9vK38MhqxPHI8/LVYvUBZYlTAjNQXhQe6Ca/nBokz
        rS1tQv1+p7sThMxSroB+U3oChcV8ivhWJhJDBS9bGDQ53CaJNOFEsuN7gzwtc4iM
        mfEzfiFCCnRV0xiGw/8xUAkqNs/IqBWvSt3+EzmcI2KNHkWah5trJbaV02htK27p
        Jrv3oytgAx/sPVC+eKsKm7BMpdy3sYnIrSW/fQSXBjjCqL6Sb9W5CHO3nFKAfeRT
        AgMBAAGjIzAhMA4GA1UdDwEB/wQEAwICpDAPBgNVHRMBAf8EBTADAQH/MA0GCSqG
        SIb3DQEBCwUAA4IBAQCdFhJwm3iNSUaMuh3EixeMlNe+iMHXV9vGDqraBTYYgnwd
        tgrSPfhDhrVHxbYhEiH+oGO7owqtVXg2o6cl6OpPOLtyzP0D6uBLXWTbXE/NXLwp
        ZjnGejDhLm4hSa1Zsxl01AO0XKcu/fSnU+LecACb3sj8JQ20kU4vUX+rOGTxNmWa
        ZC4d9XUHCcWgKyxrhl7YmlEObdXNwXGbJFLaEVC7EsmOQkvlzvC3gDWXgam4E+of
        XUkJdol0yI4qR6uNrysWbLiS4HnCMfNaFYJmPUZ5Lor++koDzYxVdISBuvbz11Px
        C9nsuB0v1FDqBBNOGgGp62Qw9/2dW2hLUS7wKw03
        -----END CERTIFICATE-----
      EOPEM
    end

    it "validates authentication with a proper response from prometheus-alert-buffer" do
      VCR.use_cassette(
        "#{described_class.name.underscore}_custom_ssl",
        # :record => :new_episodes,
      ) do
        expect(monitoring_manager.authentication_status_ok?).to be_falsey
        container_manager.authentication_check_types
        monitoring_manager.reload
        expect(monitoring_manager.authentication_status_ok?).to be_truthy
      end
    end
  end
end
