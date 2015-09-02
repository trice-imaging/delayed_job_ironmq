require_relative 'iron_mq_config'

module Delayed
  class IronMqBackend
    class << self
      attr_accessor :config, :ironmq, :default_queue, :delay, :timeout, :expires_in,
                    :available_priorities, :error_queue, :logger, :queues

      def configure
        self.default_queue ||= 'default'
        self.delay         ||= 0
        self.timeout       ||= 5.minutes
        self.expires_in    ||= 7.days
        self.error_queue   ||= 'error_queue'
        self.queues        ||= [@default_queue]

        priorities =  self.available_priorities || [0]
        if priorities.include?(0) && priorities.all? { |p| p.is_a?(Integer) }
          self.available_priorities = priorities.sort
        else
          raise ArgumentError, "available_priorities option has wrong format. Please provide array of Integer values, includes zero. Default is [0]."
        end

        self.logger       ||= Logger.new(STDOUT)
        self.logger.level ||= Logger::INFO
      end

      def all_queues
        @queues | [@default_queue]
      end
    end
  end
end


Delayed::IronMqBackend.ironmq = IronMQ::Client.new()
# initialize with defaults
Delayed::IronMqBackend.configure
