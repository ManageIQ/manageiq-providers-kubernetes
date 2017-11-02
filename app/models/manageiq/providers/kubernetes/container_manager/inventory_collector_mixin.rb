require 'thread'

module ManageIQ::Providers::Kubernetes::ContainerManager::InventoryCollectorMixin
  attr_reader   :queue
  attr_accessor :exit_requested
  private :queue, :exit_requested

  def after_initialize
    super
    @queue = Queue.new
  end

  def do_before_work_loop
    @watch_thread_id = start_watch_thread
  end

  def do_work
    if @watch_thread_id.nil? || !@watch_thread_id.alive?
      _log.info("Watch thread #{@watch_thread_id} gone, restarting...")
      @watch_thread_id = start_watch_thread
    end

    process_queue

    sleep_poll_normal
  end

  def before_exit(message, _exit_code)
    safe_log("#{message} Stopping Watch Thread.")

    stop_watch_thread

    unless @watch_thread_id.nil?
      safe_log("#{message} Waiting for Watch Thread to Stop.")
      begin
        @watch_thread_id.join(worker_settings[:watch_thread_shutdown_timeout])
      rescue => err
        safe_log("#{message} Failed to join watch thread: #{err}")
      end
    end

    process_queue
  end

  private

  def process_queue
    targets = []
    until queue.empty?
      notice = queue.deq

      targets << parse_target_from_notice(notice)
    end

    unless targets.empty?
      _log.info("Queueing refresh for #{targets.count} pods")
      EmsRefresh.queue_refresh(targets)
    end
  end

  def parse_target_from_notice(notice)
    object = notice.object

    ems_ref = parse_notice_pod_ems_ref(object)

    ManagerRefresh::Target.new(
      :manager     => ems,
      :association => :container_groups,
      :manager_ref => ems_ref,
      :options     => {
        :payload => object.to_json,
      }
    )
  end

  def stop_watch_thread
    self.exit_requested = true

    # TODO: pod_watch_stream.finish ?
  end

  def start_watch_thread
    self.exit_requested = false

    _log.info("Starting watch thread...")

    tid = Thread.new do
      begin
        watch_thread
      rescue => err
        _log.warn("Watch thread exception: #{err}")
      end
    end

    _log.info("Started watch thread [#{tid}]")

    tid
  end

  def watch_thread
    pod_watch_stream.each do |notice|
      break if exit_requested
      next if notice.type != "DELETED" && worker_settings[:deleted_notices_only]

      _log.info("EMS [#{ems.id}] Received change for pod [#{parse_notice_pod_ems_ref(notice.object)}]")

      queue.enq(notice)
    end

    _log.info("Watch thread exiting...")
  end

  def connection
    @connection ||= ems.connect(:service => "kubernetes")
  end

  def pod_watch_stream
    @pod_watch_stream ||= connection.watch_pods(watch_options)
  end

  def parse_notice_pod_ems_ref(pod)
    pod.metadata.uid
  end

  def watch_options
    {}
  end
end
