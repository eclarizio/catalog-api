module Catalog
  class UpdateOrderItem
    def initialize(topic, task)
      @payload = topic.payload
      @message = topic.message
      @task    = task
    end

    def process
      Rails.logger.info("Processing service order topic message: #{@message} with payload: #{@payload}")

      Rails.logger.info("Searching for OrderItem with a task_ref: #{@payload["task_id"]}")
      @order_item = find_order_item
      Rails.logger.info("Found OrderItem: #{@order_item.id}")

      @order_item.update_message("info", "Task update message received with payload: #{@payload}")

      mark_item_based_on_status
    end

    private

    def find_order_item
      OrderItem.find_by!(:topology_task_ref => @payload["task_id"])
    rescue ActiveRecord::RecordNotFound
      Rails.logger.error("Could not find an OrderItem with topology_task_ref: #{@payload["task_id"]}")
      raise "Could not find an OrderItem with topology_task_ref: #{@payload["task_id"]}"
    end

    def mark_item_based_on_status
      case @payload["status"]
      when "ok"
        case @payload["state"]
        when "completed"
          @order_item.mark_completed("Order Item Complete", :service_instance_ref => service_instance_id)
        when "running"
          @order_item.update_message("info", "Order Item being processed with context: #{@payload["context"]}")
          @order_item.update!(:external_url => @task.context.dig(:service_instance, :url))
        end
      when "error"
        @order_item.mark_failed("Order Item Failed", :service_instance_ref => service_instance_id)
      else
        # Do nothing for now, only other case is "warn"
      end
    end

    def service_instance_id
      @service_instance_id ||= @task.context.dig(:service_instance, :id) || @order_item.service_instance_ref
    end
  end
end
