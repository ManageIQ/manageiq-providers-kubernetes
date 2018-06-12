module ManageIQ::Providers::Kubernetes::VirtualizationManagerMixin
  extend ActiveSupport::Concern

  ENDPOINT_ROLE = :kubevirt

  included do
    delegate :authentication_check,
             :authentication_for_summary,
             :authentication_status,
             :authentication_token,
             :authentications,
             :endpoints,
             :zone,
             :to        => :parent_manager,
             :allow_nil => true

    def self.hostname_required?
      false
    end
  end

  module ClassMethods
    def raw_connect(options)
      ManageIQ::Providers::Kubevirt::InfraManager.raw_connect(options)
    end
  end

  def virtualization_endpoint
    connection_configurations.kubevirt.try(:endpoint)
  end

  def default_authentication_type
    ENDPOINT_ROLE
  end
end
