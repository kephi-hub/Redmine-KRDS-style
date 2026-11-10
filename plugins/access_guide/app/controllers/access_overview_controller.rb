# 관리 > 권한 한눈에 보기 (관리자 전용, 조회만)
class AccessOverviewController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :access_overview
  helper :access_overview
  before_action :require_admin

  def index
    @roles = Role.givable.sorted.to_a
    @closed_ids = IssueStatus.where(is_closed: true).pluck(:id)
    @trackers = Tracker.sorted.to_a
    @missing = @roles.to_h do |r|
      have = WorkflowTransition.where(role_id: r.id).distinct.pluck(:tracker_id)
      [r.id, @trackers.reject { |t| have.include?(t.id) }]
    end
    @projects = Project.active.sorted.to_a
    @users = User.active.sorted.to_a
    @memberships = Member.joins(:project).merge(Project.active).includes(:roles, :principal, :project).to_a
                         .group_by(&:user_id)
  end
end
