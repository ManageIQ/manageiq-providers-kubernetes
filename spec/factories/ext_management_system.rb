FactoryBot.define do
  factory :ems_kubernetes_with_zone, :parent => :ems_kubernetes do
    zone do
      _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
      zone
    end
  end

  trait :with_metrics_endpoint do
    after(:create) do |ems|
      ems.endpoints << FactoryBot.create(:endpoint, :role => "prometheus")
      ems.authentications << FactoryBot.create(:authentication, :authtype => "prometheus", :status => "Valid")
    end
  end

  trait :with_invalid_auth do
    after(:create) do |ems|
      ems.authentications.update_all(:status => "invalid")
    end
  end
end
