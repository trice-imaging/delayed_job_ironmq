module Delayed
  module Backend
    module Ironmq
      class Job
        include ::DelayedJobIronmq::Document
        include Delayed::Backend::Base
        extend  Delayed::Backend::Ironmq::Actions

        field :priority,    :type => Integer, :default => 0
        field :attempts,    :type => Integer, :default => 0
        field :handler,     :type => String
        field :run_at,      :type => Time
        field :locked_at,   :type => Time
        field :locked_by,   :type => String
        field :failed_at,   :type => Time
        field :last_error,  :type => String
        field :queue,       :type => String
        field :created_at,  :type => Time

        def initialize(data = {})
          @msg = nil
          if data.is_a?(IronMQ::Message)
            @msg = data
            data = JSON.load(data.body)
          end

          data.symbolize_keys!
          payload_obj = data.delete(:payload_object) || data.delete(:handler)

          @default_queue   = data[:default_queue]   || IronMqBackend.default_queue
          @delay           = data[:delay]           || IronMqBackend.delay
          @expires_in      = data[:expires_in]      || IronMqBackend.expires_in
          @error_queue     = data[:error_queue]     || IronMqBackend.error_queue
          @max_run_time    = data[:max_run_time]    || Worker.max_run_time
          @attributes    = data
          self.payload_object = payload_obj

          initialize_queue
        end

        def payload_object
          @payload_object ||= yaml_load
        rescue TypeError, LoadError, NameError, ArgumentError => e
          raise DeserializationError,
            "Job failed to load: #{e.message}. Handler: #{handler.inspect}"
        end

        def payload_object=(object)
          if object.is_a? String
            @payload_object = yaml_load(object)
            self.handler = object
          else
            @payload_object = object
            self.handler = object.to_yaml
          end
        end

        def save
          if @attributes[:handler].blank?
            raise "Handler missing!"
          end
          payload = JSON.dump(@attributes)

          if run_at && run_at.utc >= self.class.db_time_now
            @delay = (run_at.utc - self.class.db_time_now).round
          end

          @msg.delete if @msg

          ironmq.queue(queue_name).post(payload, delay: @delay)
          true
        end

        def save!
          save
        end

        # find better way to remove a timed out message
        def destroy
          @msg.delete
        rescue
          @msg = ironmq.queue(queue_name).get_message(@msg.id)
          @msg.delete
        end

        def fail!
          ironmq.queue(@error_queue).post(@msg.body, delay: @delay)
          destroy
        end

        def update_attributes(attributes)
          attributes.symbolize_keys!
          @attributes.merge attributes
          save
        end

        # No need to check locks
        def lock_exclusively!(*args)
          true
        end

        # Reget a message(job) after max_run_time(timeout) to delete
        def unlock(*args)
          @msg = ironmq.queue(queue_name).get_message(@msg.id)
        end

        def reload(*args)
          # reset
          super
        end

        def id
          @msg.id if @msg
        end

        private

        def queue_name
          "#{@attributes[:queue] || @default_queue}_#{@attributes[:priority] || 0}"
        end

        def ironmq
          ::Delayed::IronMqBackend.ironmq
        end

        def yaml_load(object)
          object ||= self.handler
          YAML.respond_to?(:load_dj) ? YAML.load_dj(object) : YAML.load(object)
        end

        def initialize_queue
          ironmq.queue(queue_name).info
        rescue
          ironmq.create_queue(queue_name, message_timeout: @max_run_time.to_i,
                                          message_expiration: @expires_in.to_i)
        end
      end
    end
  end
end
