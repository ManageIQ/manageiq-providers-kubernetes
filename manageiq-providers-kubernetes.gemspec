$:.push File.expand_path("../lib", __FILE__)

require "manageiq/providers/kubernetes/version"

Gem::Specification.new do |s|
  s.name        = "manageiq-providers-kubernetes"
  s.version     = ManageIQ::Providers::Kubernetes::VERSION
  s.authors     = ["ManageIQ Developers"]
  s.homepage    = "https://github.com/ManageIQ/manageiq-providers-kubernetes"
  s.summary     = "Kubernetes Provider for ManageIQ"
  s.description = "Kubernetes Provider for ManageIQ"
  s.licenses    = ["Apache-2.0"]

  s.files = Dir["{app,config,lib}/**/*"]

  s.add_runtime_dependency("hawkular-client",                 "~> 5.0")
  s.add_runtime_dependency("image-inspector-client",          "~> 2.0")
  s.add_runtime_dependency("kubeclient",                      "~> 4.6")
  s.add_runtime_dependency("more_core_extensions",            ">= 3.6", "< 5")
  s.add_runtime_dependency("prometheus-alert-buffer-client",  "~> 0.3.0")
  s.add_runtime_dependency("prometheus-api-client",           "~> 0.6")

  s.add_development_dependency("codeclimate-test-reporter", "~> 1.0.0")
  s.add_development_dependency("recursive-open-struct",     "~> 1.0.0")
  s.add_development_dependency("simplecov")
end
