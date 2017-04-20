module ManageIQ
  module Providers
    module Kubernetes
      class Engine < ::Rails::Engine
        isolate_namespace ManageIQ::Providers::Kubernetes
      end
    end
  end
end
