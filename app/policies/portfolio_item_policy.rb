class PortfolioItemPolicy < ApplicationPolicy
  def index?
    rbac_access.permission_check('read', Portfolio)
  end

  def create?
    portfolio_id = @record.class == Portfolio ? @record.id : @record.portfolio_id
    rbac_access.resource_check('update', portfolio_id, Portfolio)
  end

  def update?
    rbac_access.resource_check('update', @record.portfolio_id, Portfolio)
  end

  def destroy?
    rbac_access.resource_check('update', @record.portfolio_id, Portfolio)
  end

  def copy?
    destination_id = @user.try(:params).try(:dig, :portfolio_id) || @record.portfolio_id

    if destination_id == @record.portfolio_id
      can_read_and_update_destination?(destination_id)
    else
      rbac_access.resource_check('read', @record.portfolio_id, Portfolio) &&
        can_read_and_update_destination?(destination_id)
    end
  end

  def edit_survey?
    rbac_access.resource_check('update', @record.portfolio_id, Portfolio)
  end

  def set_approval?
    rbac_access.resource_check('update', @record.portfolio_id, Portfolio) &&
      rbac_access.approval_workflow_check
  end

  private

  def can_read_and_update_destination?(destination_id)
    rbac_access.resource_check('read', destination_id, Portfolio) &&
      rbac_access.resource_check('update', destination_id, Portfolio)
  end

  class Scope < Scope
    def resolve
      if access_scopes.include?('admin')
        scope.all
      elsif access_scopes.include?('group')
        ids = Catalog::RBAC::AccessControlEntries.new(@user_context.group_uuids).ace_ids('read', Portfolio)
        scope.where(:portfolio_id => ids)
      elsif access_scopes.include?('user')
        scope.by_owner
      else
        Rails.logger.error("Error in scope search for #{scope.table_name}")
        Rails.logger.error("Scope does not include admin, group, or user. List of scopes: #{access_scopes}")
        raise Catalog::NotAuthorized, "Not Authorized for #{scope.table_name}"
      end
    end
  end
end
