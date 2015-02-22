module Delayed
  module Backend
    module Ironmq
      module Actions
        def field(name, options = {})
          #type   = options[:type]    || String
          default = options[:default] || nil
          define_method name do
            @attributes ||= {}
            @attributes[name.to_sym] || default
          end
          define_method "#{name}=" do |value|
            @attributes ||= {}
            @attributes[name.to_sym] = value
          end
        end

        def before_fork
        end

        def after_fork
        end

        def db_time_now
          Time.now.utc
        end

        #def self.queue_name
        #  Delayed::Worker.queue_name
        #end

        def find_available(worker_name, limit = 5, max_run_time = Worker.max_run_time)
          Delayed::Worker.available_priorities.each do |priority|
            begin
              message = ironmq.queue(queue_name(priority)).get
            rescue Exception => e
              Delayed::Worker.logger.warn(e.message)
            end
            return [Delayed::Backend::Ironmq::Job.new(message)] if message
          end
          []
        end

        def delete_all
          deleted = 0
          Delayed::Worker.available_priorities.each do |priority|
            loop do
              begin
                msgs = ironmq.queue(queue_name(priority)).get(:n => 1000)
              rescue Exception => e
                Delayed::Worker.logger.warn(e.message)
              end

              break if msgs.blank?
              msgs.each do |msg|
                msg.delete
                deleted += 1
              end
            end
          end
        end

        # No need to check locks
        def clear_locks!(*args)
          true
        end

        private

        def ironmq
          ::Delayed::Worker.ironmq
        end

        def queue_name(priority)
          "#{Delayed::Worker.queue_name}_#{priority || 0}"
        end
      end
    end
  end
end
