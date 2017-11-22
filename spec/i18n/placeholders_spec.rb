describe :placeholders do
  include_examples :placeholders, ManageIQ::Providers::Kubernetes::Engine.root.join('locale').to_s
end
