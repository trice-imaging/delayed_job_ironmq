require 'delayed_job_ironmq.rb'

class SimpleJob
  # cattr_accessor :runs
  @runs = 0
  def perform
    self.class.runs += 1
  end
end

describe 'DelayedJobIronmq' do
  let(:ironmq) { instance_double("IronMQ::Client") }
  let(:queue) { instance_double("IronMQ::Queue") }
  let(:job_handler_str) { "--- !ruby/object:Delayed::PerformableMethod\\nobject: !ruby/object:SimpleJob {}\\nmethod_name: :perform\\nargs: []\\n" }

  before do
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
      expect(queue).to receive(:post).with("{\"priority\":0,\"queue\":null,\"handler\":\"#{job_handler_str}\"}", {:delay=>0})

      SimpleJob.new.delay.perform
    end

    it 'passes on a proper delay' do
      run_at = Time.now + 5.minutes
      expect(queue).to receive(:post).with("{\"run_at\":\"#{run_at.to_s}\",\"priority\":0,\"queue\":null,\"handler\":\"#{job_handler_str}\"}", {:delay=>300})

      SimpleJob.new.delay(run_at: run_at).perform
    end
  end


end
