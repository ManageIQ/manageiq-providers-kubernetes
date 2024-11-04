module ManageIQ::Providers::Kubernetes::ContainerManager::Options
  extend ActiveSupport::Concern

  module ClassMethods
    def proxy_settings
      {
        :http_proxy => {
          :label          => N_('HTTP Proxy'),
          :help_text      => N_('HTTP Proxy to connect ManageIQ to the provider. example: http://user:password@my_https_proxy'),
          :global_default => VMDB::Util.http_proxy_uri,
        },
      }
    end

    def advanced_settings
      {
        :image_inspector_options => {
          :label     => N_('Image Inspector Options'),
          :help_text => N_('Settings for Image Inspector tool'),
          :settings  => {
            :http_proxy  => {
              :label     => N_('HTTP Proxy'),
              :help_text => N_('HTTP Proxy to connect image inspector pods to the internet. example: http://user:password@my_https_proxy'),
            },
            :https_proxy => {
              :label     => N_('HTTPS Proxy'),
              :help_text => N_('HTTPS Proxy to connect image inspector pods to the internet. example: https://user:password@my_https_proxy'),
            },
            :no_proxy    => {
              :label     => N_('No Proxy'),
              :help_text => N_('No Proxy lists urls that should\'nt be sent to any proxy. example: my_file_server.org'),
            },
            :repository  => {
              :label          => N_('Image-Inspector Repository'),
              :help_text      => N_('Image-Inspector Repository. example: openshift/image-inspector'),
              :global_default => ::Settings.ems.ems_kubernetes.image_inspector_repository,
            },
            :registry    => {
              :label          => N_('Image-Inspector Registry'),
              :help_text      => N_('Registry to provide the image inspector repository. example: docker.io'),
              :global_default => ::Settings.ems.ems_kubernetes.image_inspector_registry,
            },
            :image_tag   => {
              :label          => N_('Image-Inspector Tag'),
              :help_text      => N_('Image-Inspector image tag. example: 2.1'),
              :global_default => ManageIQ::Providers::Kubernetes::ContainerManager::Scanning::Job::INSPECTOR_IMAGE_TAG,
            },
            :cve_url     => {
              :label          => N_('CVE Location'),
              :help_text      => N_('Alternative URL path for the XCCDF file, where a com.redhat.rhsa-RHEL7.ds.xml.bz2 file is expected. example: http://my_file_server.example.org:3333/xccdf_files/'),

              # Future versions of image inspector will extend this.
              :global_default => ::Settings.ems.ems_kubernetes.image_inspector_cve_url,
            },
          }
        }
      }
    end

    def options_description
      {
        :proxy_settings    => {
          :label     => N_('Proxy Settings'),
          :help_text => N_('Proxy Settings for connection to the provider'),
          :settings  => proxy_settings,
        },
        :advanced_settings => {
          :label     => N_('Advanced Settings'),
          :help_text => N_('Advanced Settings for provider configuration'),
          :settings  => advanced_settings,
        }
      }
    end
  end
end
