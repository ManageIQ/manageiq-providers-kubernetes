if ENV['CI']
  require 'simplecov'
  SimpleCov.start
end

VCR.configure do |config|
  config.ignore_hosts 'codeclimate.com' if ENV['CI']
  config.cassette_library_dir = File.join(ManageIQ::Providers::Kubernetes::Engine.root, 'spec/vcr_cassettes')
end

# Helps constructing inputs similar to kubeclient results
module ArrayRecursiveOpenStruct
  def array_recursive_ostruct(hash)
    RecursiveOpenStruct.new(hash, :recurse_over_arrays => true)
  end
end

RSpec.configure do |c|
  c.include ArrayRecursiveOpenStruct
  c.extend ArrayRecursiveOpenStruct
end

Dir[Rails.root.join("spec/shared/**/*.rb")].each { |f| require f }
Dir[ManageIQ::Providers::Kubernetes::Engine.root.join("spec/support/**/*.rb")].each { |f| require f }
