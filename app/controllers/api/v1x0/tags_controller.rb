module Api
  module V1x0
    class TagsController < ApplicationController
      include Api::V1x0::Mixins::IndexMixin
      include Insights::API::Common::TaggingMethods

      def index
        if params[:portfolio_id]
          scope = Portfolio.where(:id => params.require(:portfolio_id))
          relevant_portfolio = policy_scope(scope, :policy_scope_class => PortfolioPolicy::Scope).first
          raise ActiveRecord::RecordNotFound unless relevant_portfolio
          relevant_tags = relevant_portfolio.tags || Tag.none

          collection(relevant_tags, :pre_authorized => true)
        elsif params[:portfolio_item_id]
          scope = PortfolioItem.where(:id => params.require(:portfolio_item_id))
          relevant_portfolio_item = policy_scope(scope, :policy_scope_class => PortfolioItemPolicy::Scope).first
          raise ActiveRecord::RecordNotFound unless relevant_portfolio_item
          relevant_tags = relevant_portfolio_item.tags || Tag.none

          collection(relevant_tags, :pre_authorized => true)
        else
          collection(Tag.all)
        end
      end

      private

      def instance_link(instance)
        endpoint = instance.class.name.underscore
        version  = self.class.send(:api_version)
        send("api_#{version}_#{endpoint}_url", instance.id)
      end
    end
  end
end
