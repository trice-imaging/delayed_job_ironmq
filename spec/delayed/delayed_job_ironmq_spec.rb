require 'delayed_job_ironmq.rb'

class SimpleJob
  # cattr_accessor :runs
  @runs = 0
  def perform
    a = 0 / 0
    self.class.runs += 1
    Delayed::Worker.logger.info "ran #{self.class.runs} times"
  end
end

class ErrorJob
  def perform
    Delayed::Worker.logger.info "PERFORM RUNNING"
    raise NoMethodError, "Hello! I should fail."
  end
end

describe 'DelayedJobIronmq' do
  let(:ironmq) { instance_double("IronMQ::Client") }
  let(:queue) { instance_double("IronMQ::Queue") }
  let(:error_queue) { instance_double("IronMQ::Queue") }
  let(:job_handler_str) { "--- !ruby/object:Delayed::PerformableMethod\nobject: !ruby/object:SimpleJob {}\nmethod_name: :perform\nargs: []\n" }
  let(:job_handler_str_esc) { job_handler_str.gsub "\n", "\\n" }
  let(:error_job_handler_str) { "--- !ruby/object:Delayed::PerformableMethod\nobject: !ruby/object:ErrorJob {}\nmethod_name: :perform\nargs: []\n" }

  before do
    Delayed::Worker.logger = Logger.new(STDOUT)

    allow(Delayed::IronMqBackend).to receive(:ironmq) { ironmq }
    allow(queue).to receive_messages(
      info: {},
      post: nil
    )
  end

  describe 'Queue Creation' do
    before do
      @queue_called = 0
      allow(ironmq).to receive(:queue) do
        @queue_called += 1
        if @queue_called == 1
          raise StandardError
        else
          queue
        end
      end

      allow(ironmq).to receive(:create_queue) { queue }
    end

    it 'creates a queue with default settings on first enqueue' do
      expect(ironmq).to receive(:create_queue).with("default_0", {:message_timeout=>14405, :message_expiration=>604800})
      SimpleJob.new.delay.perform
    end

    it 'creates a named queue' do
      expect(ironmq).to receive(:queue).with("other_queue_0")
      expect(ironmq).to receive(:create_queue).with("other_queue_0", {:message_timeout=>14405, :message_expiration=>604800})

      SimpleJob.new.delay(queue: "other_queue").perform
    end

    it 'creates a named queue with different priority' do
      expect(ironmq).to receive(:queue).with("other_queue_1")
      expect(ironmq).to receive(:create_queue).with("other_queue_1", {:message_timeout=>14405, :message_expiration=>604800})

      SimpleJob.new.delay(queue: "other_queue", priority: 1).perform
    end
  end

  describe 'Posting Jobs' do
    before do
      allow(ironmq).to receive(:queue) { queue }
    end

    it 'posts to the default queue' do
      expect(ironmq).to receive(:queue).with("default_0")
      expect(queue).to receive(:post).with("{\"priority\":0,\"queue\":null,\"handler\":\"#{job_handler_str_esc}\"}", {:delay=>0})

      SimpleJob.new.delay.perform
    end

    it 'passes on a proper delay' do
      time = Time.now
      allow(Time).to receive(:now).and_return(time)
      run_at = Time.now + 5.minutes
      expect(queue).to receive(:post).with("{\"run_at\":\"#{run_at.to_s}\",\"priority\":0,\"queue\":null,\"handler\":\"#{job_handler_str_esc}\"}", {:delay=>300})

      SimpleJob.new.delay(run_at: run_at).perform
    end
  end

  describe 'Recieving Jobs' do
    before do
      @messages_got = 0
      allow(ironmq).to receive(:queue) { queue }
      allow(queue).to receive(:get) do
        @messages_got += 1
        @messages_got == 1 ? {"priority"=>0, "queue"=>nil, "handler"=>job_handler_str} : nil
      end
      # allow(queue).to receive(:get_message) { "{\"priority\":0,\"queue\":null,\"handler\":\"#{job_handler_str}\"}" }
    end

    it 'executes a job' do
      # job = SimpleJob.new
      # expect(queue).to receive(:get)
      # expect(Delayed::Job).to receive(:reserve)

      expect_any_instance_of(SimpleJob).to receive(:perform)
      # expect_any_instance_of(Delayed::Backend::Ironmq::Job).to receive(:destroy)

      # SimpleJob.new.delay.perform
      Delayed::Worker.new.work_off

      expect(queue).to have_received(:get).twice
    end

  end

  describe 'Failing Jobs' do
    def message_factory(body, id: 123, reservation_id: 'def456')
      IronMQ::Message.new(queue, {
        "id" => id,
        "body" => body,
        "reserved_count" => 1,
        "reservation_id" => reservation_id
      })
    end

    before do
      body = {"priority"=>0, "queue"=>nil, "handler"=>error_job_handler_str}.to_json
      @message = message_factory(body)

      allow(ironmq).to receive(:queue).with('default_0') { queue }
      allow(ironmq).to receive(:queue).with('error_queue') { error_queue }
      allow(queue).to receive(:post) do |payload, delay|
        @message = message_factory(payload)
      end

      allow(queue).to receive(:get) do
        temp = @message
        @message = nil
        temp
      end
      allow(queue).to receive(:get_message) { {"priority"=>0, "queue"=>nil, "handler"=>error_job_handler_str} }
      allow(queue).to receive(:call_api_and_parse_response)
      allow(error_queue).to receive(:post)
    end

    it 'retries a failed job and moves it to the error queue after max_attempts' do
      Delayed::Worker.destroy_failed_jobs = false
      Delayed::Worker.max_attempts = 2

      # Delayed::Worker.delay_jobs = false
      puts "Delayed::Worker.destroy_failed_jobs: #{Delayed::Worker.destroy_failed_jobs}"
      puts "Delayed::Worker.max_attempts: #{Delayed::Worker.max_attempts}"
      puts "Delayed::Worker.delay_jobs: #{Delayed::Worker.delay_jobs}"

      expect(queue).to receive(:post)
      expect(queue).to receive(:call_api_and_parse_response).with(:delete, "/messages/123", {:reservation_id=>"def456"}, true)
      expect(error_queue).to receive(:post)

      Delayed::Worker.new.work_off

      expect(queue).to have_received(:get).exactly(3).times
    end
  end


end
