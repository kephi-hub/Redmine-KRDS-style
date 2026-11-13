# 관리 > 업무흐름 간편 설정 — 역할마다 상태 전환표 하나를 여러 일감 유형에 한 번에 적용
# 기본 전환(작성자·담당자 조건 없는 것)만 바꾸고, 작성자·담당자 추가 규칙과 필드 권한은 그대로 둠
class SimpleWorkflowsController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :simple_workflows
  helper :access_overview
  before_action :require_admin
  before_action :load_common

  def index
    @role = @roles.find { |r| r.id == params[:role_id].to_i } || @roles.first
    return unless @role
    rows = WorkflowTransition.where(role_id: @role.id, author: false, assignee: false).pluck(:tracker_id, :old_status_id, :new_status_id)
    @per_tracker = rows.group_by(&:first).transform_values { |v| v.map { |(_, a, b)| [a, b] }.to_set }
    @count = Hash.new(0)
    @trackers.each { |t| (@per_tracker[t.id] || []).each { |pair| @count[pair] += 1 } }
  end

  def update
    role = @roles.find { |r| r.id == params[:role_id].to_i } or return render_404
    tracker_ids = Array(params[:tracker_ids]).map(&:to_i) & @trackers.map(&:id)
    if tracker_ids.empty?
      flash[:error] = l(:error_simple_workflow_no_tracker)
      return redirect_to simple_workflows_path(role_id: role.id)
    end
    status_ids = @statuses.map(&:id)
    table = params[:t].respond_to?(:to_unsafe_h) ? params[:t].to_unsafe_h : {} # 모두 해제하면 t 가 오지 않음
    pairs = table.flat_map { |from, tos| Array(tos).map { |to| [from.to_i, to.to_i] } }
                              .select { |a, b| a != b && status_ids.include?(a) && status_ids.include?(b) }.uniq
    WorkflowTransition.transaction do
      # 출발 상태 0(새 일감을 만들 때 고를 수 있는 시작 상태)은 이 화면에서 다루지 않으므로 지우지 않음
      WorkflowTransition.where(role_id: role.id, tracker_id: tracker_ids, author: false, assignee: false).where.not(old_status_id: 0).delete_all
      rows = tracker_ids.flat_map do |tid|
        pairs.map { |a, b| { type: 'WorkflowTransition', role_id: role.id, tracker_id: tid, old_status_id: a, new_status_id: b, author: false, assignee: false } }
      end
      WorkflowTransition.insert_all(rows) if rows.any?
    end
    flash[:notice] = l(:notice_simple_workflow_saved, role: role.name, count: tracker_ids.size, pairs: pairs.size)
    redirect_to simple_workflows_path(role_id: role.id)
  end

  private

  def load_common
    @roles = Role.givable.sorted.to_a
    @trackers = Tracker.sorted.to_a
    @statuses = IssueStatus.sorted.to_a
  end
end
