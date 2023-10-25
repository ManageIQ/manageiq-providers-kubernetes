require 'kubeclient'

module ManageIQ
  module Providers
    module Kubernetes
      module DebugKubeclientWatch
        def build_client
          super.use(logging: { logger: Logger.new($stderr) })
        end
      end
    end
  end
end
