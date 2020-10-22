# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'manageiq/providers/kubernetes/version'

Gem::Specification.new do |spec|
  spec.name          = "manageiq-providers-kubernetes"
  spec.version       = ManageIQ::Providers::Kubernetes::VERSION
  spec.authors       = ["ManageIQ Authors"]

  spec.summary       = "ManageIQ plugin for the Kubernetes provider."
  spec.description   = "ManageIQ plugin for the Kubernetes provider."
  spec.homepage      = "https://github.com/ManageIQ/manageiq-providers-kubernetes"
  spec.license       = "Apache-2.0"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "hawkular-client",                 "~> 5.0"
  spec.add_dependency "image-inspector-client",          "~> 2.0"
  spec.add_dependency "kubeclient",                      "~> 4.6"
  spec.add_dependency "more_core_extensions",            ">= 3.6", "< 5"
  spec.add_dependency "prometheus-alert-buffer-client",  "~> 0.3.0"
  spec.add_dependency "prometheus-api-client",           "~> 0.6"

  spec.add_development_dependency "manageiq-style"
  spec.add_development_dependency "recursive-open-struct", "~> 1.0.0"
  spec.add_development_dependency "simplecov"
end
