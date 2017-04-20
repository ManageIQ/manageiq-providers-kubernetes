Vmdb::Gettext::Domains.add_domain(
  'ManageIQ_Providers_Kubernetes',
  ManageIQ::Providers::Kubernetes::Engine.root.join('locale').to_s,
  :po
)
