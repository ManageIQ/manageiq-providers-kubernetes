#
# This mixin implements the `alert_labels` feature.
#
module ManageIQ::Providers::Kubernetes::ContainerManager::AlertLabels
  extend ActiveSupport::Concern

  #
  # Any provider that includes this mix-in will support the alert lables, populated from the labels
  # provided by Prometheus.
  #
  included do
    supports :alert_labels
  end

  #
  # Returns the alert labels associated to the given alert status.
  #
  # @param alert_status [MiqAlertStatus] The alert status object.
  # @return [Array<MiqAlertStatusLabel>] The array of labels.
  #
  def alert_labels(alert_status)
    # Find the event that correspond to the given alert status:
    event = EventStream.find_by(
      :ems_id  => alert_status.ems_id,
      :ems_ref => alert_status.event_ems_ref
    )
    return [] unless event

    # Extract the hash of labels from the event full data:
    labels = event.full_data && event.full_data['labels']
    return [] unless labels

    # Convert the hash to an array of label objects:
    labels.map do |name, value|
      label = MiqAlertStatusLabel.new
      label.name = name
      label.value = value
      label
    end
  end
end
