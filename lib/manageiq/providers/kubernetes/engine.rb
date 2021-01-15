module ManageIQ
  module Providers
    module Kubernetes
      class Engine < ::Rails::Engine
        isolate_namespace ManageIQ::Providers::Kubernetes

        config.autoload_paths << root.join('lib').to_s

        def self.vmdb_plugin?
          true
        end

        def self.plugin_name
          _('Kubernetes Provider')
        end

        def self.init_loggers
          $kube_log ||= Vmdb::Loggers.create_logger("kube.log")
          $cn_monitoring_log ||= Vmdb::Loggers.create_logger("cn_monitoring.log")
        end

        def self.apply_logger_config(config)
          Vmdb::Loggers.apply_config_value(config, $kube_log, :level_kube)
          Vmdb::Loggers.apply_config_value(config, $cn_monitoring_log, :level_cn_monitoring)
        end
      end
    end
  end
end
