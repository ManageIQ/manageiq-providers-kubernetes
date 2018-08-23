module ManageIQ
  module Providers
    module Kubernetes
      class Engine < ::Rails::Engine
        isolate_namespace ManageIQ::Providers::Kubernetes

        def self.plugin_name
          _('Kubernetes Provider')
        end
      end
    end
  end
end
