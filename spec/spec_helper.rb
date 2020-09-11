if ENV['CI']
  require 'simplecov'
  SimpleCov.start
end

Dir[Rails.root.join("spec/shared/**/*.rb")].each { |f| require f }
# NOTE: This repo's spec/support/ is also used by manageiq-providers-openshift.
Dir[File.join(__dir__, "support/**/*.rb")].each { |f| require f }

require "manageiq-providers-kubernetes"

VCR.configure do |config|
  config.ignore_hosts 'codeclimate.com' if ENV['CI']
  config.cassette_library_dir = File.join(ManageIQ::Providers::Kubernetes::Engine.root, 'spec/vcr_cassettes')
end
