class ManageIQ::Providers::Kubernetes::Prometheus::MessageBufferClient
  require 'faraday'
  require 'faraday_middleware'

  def initialize(host, port)
    @host = host
    @port = port
  end

  def alert_url
    "https://#{@host}:#{@port}/topics/alerts"
  end

  def connect(client_options)
    settings = ::Settings.ems.ems_kubernetes.ems_monitoring.alerts_collection
    Faraday.new(
      :url     => alert_url,
      :headers => {'Authorization' => "Bearer #{client_options[:bearer]}"},
      :request => {
        # opening a connection
        :open_timeout => settings.open_timeout.to_f_with_method,
        # waiting for response
        :timeout      => settings.timeout.to_f_with_method,
      },
      :ssl     => {
        :verify     => client_options[:verify_ssl],
        :cert_store => client_options[:cert_store],
      },
    ) do |conn|
      conn.response(:json)
      conn.adapter(Faraday.default_adapter)
    end
  end
end
