class ManageIQ::Providers::Kubernetes::ContainerManager::EventCatcher::Runner < ManageIQ::Providers::BaseManager::EventCatcher::Runner
  include ManageIQ::Providers::Kubernetes::ContainerManager::EventCatcherMixin

  private

  def worker_options
    options = super
    options[:settings] = worker_settings
    options[:ems].each do |manager|
      manager_record = ExtManagementSystem.find(manager["id"])
      manager["authentications"].each do |authentication|
        auth_type = authentication["authtype"]
        authentication["password"] = manager_record.authentication_password(auth_type)
        authentication["auth_key"] = manager_record.authentication_key(auth_type)
      end
    end
    options
  end
end
