require 'topological_inventory-api-client'
class TopologicalInventory
  def self.api
    Thread.current[:api_instance] ||= raw_api
  end

  def self.call
    pass_thru_headers
    yield api
  rescue TopologicalInventoryApiClient::ApiError => err
    Rails.logger.error("TopologicalInventoryApiClient::ApiError #{err.message} ")
    raise Catalog::TopologyError, err.message
  end

  private_class_method def self.raw_api
    TopologicalInventoryApiClient.configure do |config|
      config.host = ENV['TOPOLOGICAL_INVENTORY_URL'] || 'localhost'
      config.scheme = URI.parse(ENV['TOPOLOGICAL_INVENTORY_URL']).try(:scheme) || 'http'
      dev_credentials(config)
    end
    TopologicalInventoryApiClient::DefaultApi.new
  end

  private_class_method def self.pass_thru_headers
    headers = Insights::API::Common::Request.current_forwardable
    api.api_client.default_headers = api.api_client.default_headers.merge(headers)
  end
end
