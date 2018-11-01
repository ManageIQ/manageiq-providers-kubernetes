FactoryGirl.define do
  factory :ems_kubernetes_with_zone, :parent => :ems_kubernetes do
    zone do
      _guid, _server, zone = EvmSpecHelper.create_guid_miq_server_zone
      zone
    end
  end
end
