# 프로젝트 > 요구사항 > 변경요청 — 접수 → 영향 분석 → 승인/반려 → 반영 완료, 연결(요구사항·메뉴·인터페이스·일감), 반영 일감 만들기, 엑셀
class PmChangeRequestsController < ApplicationController
  menu_item :change_requests
  helper :pm_docs
  include PmDocsHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_cr, only: [:show, :edit, :update, :destroy, :decide, :make_issue]

  def index
    all = PmChangeRequest.where(project_id: @project.id).includes(:pm_cr_links, :decided_by).sorted.to_a
    @kpi = PmChangeRequest::STATUSES.to_h { |s| [s, all.count { |c| c.status == s }] }
    @kpi['all'] = all.size
    @effort = all.select { |c| %w(approved done).include?(c.status) }.sum { |c| c.effort.to_f }
    @status = params[:status].presence_in(PmChangeRequest::STATUSES)
    @q = params[:q].to_s.strip
    list = all
    list = list.select { |c| c.status == @status } if @status
    list = list.select { |c| [c.code, c.title, c.description, c.requester].compact.any? { |v| v.downcase.include?(@q.downcase) } } if @q.present?
    @crs = list
  end

  def show
    @issues = @cr.issues
    @all_closed = @issues.any? && @issues.all?(&:closed?)
  end

  def new
    @cr = PmChangeRequest.new(project: @project, requested_on: User.current.today, priority: 'normal', status: 'received')
    @cr_req_ids = Array(params[:requirement_id]).map(&:to_i)
    load_form
  end

  def create
    @cr = PmChangeRequest.new(cr_params.merge(project: @project, author_id: User.current.id))
    @cr.status = 'received' unless %w(received analyzing).include?(@cr.status)
    PmChangeRequest.transaction do
      @cr.save!
      save_links
    end
    flash[:notice] = l(:notice_successful_create)
    redirect_to project_pm_change_request_path(@project, @cr)
  rescue ActiveRecord::RecordInvalid
    load_form
    render :new
  end

  def edit
    load_form
  end

  def update
    @cr.assign_attributes(cr_params.except(:status))
    @cr.status = params[:pm_change_request][:status] if %w(received analyzing).include?(params.dig(:pm_change_request, :status)) && !@cr.decided?
    PmChangeRequest.transaction do
      @cr.save!
      save_links
    end
    flash[:notice] = l(:notice_successful_update)
    redirect_to project_pm_change_request_path(@project, @cr)
  rescue ActiveRecord::RecordInvalid
    load_form
    render :edit
  end

  def destroy
    @cr.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_pm_change_requests_path(@project)
  end

  # 결정: approve | reject | done | reopen (승인 권한)
  def decide
    action = params[:decision].to_s
    case action
    when 'approve', 'reject'
      @cr.status = action == 'approve' ? 'approved' : 'rejected'
      @cr.decided_by = User.current
      @cr.decided_on = User.current.today
      @cr.decision_note = params[:decision_note].to_s.strip.presence || @cr.decision_note
    when 'done' then @cr.status = 'done' if @cr.status == 'approved'
    when 'reopen' then @cr.status = 'analyzing'
    else return render_404
    end
    PmChangeRequest.transaction do
      @cr.save!
      mark_requirements if action == 'approve'
    end
    flash[:notice] = l("notice_pm_cr_#{action}")
    redirect_to project_pm_change_request_path(@project, @cr)
  end

  # 반영 일감 만들기 (승인된 변경요청)
  def make_issue
    return deny_access unless User.current.allowed_to?(:add_issues, @project)
    tracker = @project.trackers.find_by(id: params[:tracker_id]) || @project.trackers.find_by(name: '기능') || @project.trackers.first
    issue = Issue.new(project: @project, author: User.current, tracker: tracker)
    issue.status = tracker&.default_status
    issue.priority = IssuePriority.default || IssuePriority.active.first
    issue.subject = "[#{@cr.code}] #{@cr.title}".truncate(255)
    issue.description = ["변경요청: #{@cr.code} #{@cr.title}", '', @cr.description.to_s, '', "■ 영향 분석\n#{@cr.impact}"].join("\n")
    issue.assigned_to = @project.users.find_by(id: params[:assigned_to_id])
    if issue.save
      PmCrLink.create!(pm_change_request_id: @cr.id, target_type: 'issue', target_id: issue.id)
      if defined?(MenuItemIssue) && @project.module_enabled?(:menu_tree)
        @cr.menus.each { |m| MenuItemIssue.find_or_create_by!(menu_item_id: m.id, issue_id: issue.id) }
      end
      if defined?(QaRequirementIssue) && @project.module_enabled?(:qa_requirements)
        @cr.requirements.each { |r| QaRequirementIssue.find_or_create_by!(qa_requirement_id: r.id, issue_id: issue.id) }
      end
      flash[:notice] = l(:notice_pm_issue_created, id: issue.id)
    else
      flash[:error] = issue.errors.full_messages.join(', ')
    end
    redirect_to project_pm_change_request_path(@project, @cr)
  end

  def export
    send_data PmKit::Sheet.change_requests(PmChangeRequest.where(project_id: @project.id).order(:code).to_a),
              filename: "변경요청관리대장_#{@project.identifier}_#{User.current.today.strftime('%Y%m%d')}.xlsx", type: PmKit::Sheet::XLSX
  end

  private

  def find_cr
    @cr = PmChangeRequest.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def cr_params
    params.require(:pm_change_request).permit(:code, :title, :description, :reason, :requester, :requested_on, :priority, :status, :impact, :tables, :effort, :schedule_impact)
  end

  def load_form
    @req_on = defined?(QaRequirement) && @project.module_enabled?(:qa_requirements)
    @menu_on = defined?(MenuItem) && @project.module_enabled?(:menu_tree)
    @if_on = defined?(OpsInterface) && @project.module_enabled?(:ops_interfaces)
    @all_reqs = @req_on ? QaRequirement.where(project_id: @project.id).alive.to_a.sort_by { |r| [QaRequirement.category_order(r.category), r.code] } : []
    @ordered = @menu_on ? MenuItem.ordered(@project) : []
    @all_ifs = @if_on ? OpsInterface.where(project_id: @project.id).sorted.to_a : []
  end

  def save_links
    if params[:reqs_sent] == '1' && defined?(QaRequirement)
      @cr.set_links('requirement', Array(params[:requirement_ids]).map(&:to_i) & QaRequirement.where(project_id: @project.id).pluck(:id))
    end
    if params[:menus_sent] == '1' && defined?(MenuItem)
      @cr.set_links('menu', Array(params[:menu_item_ids]).map(&:to_i) & MenuItem.where(project_id: @project.id).pluck(:id))
    end
    if params[:ifs_sent] == '1' && defined?(OpsInterface)
      @cr.set_links('interface', Array(params[:interface_ids]).map(&:to_i) & OpsInterface.where(project_id: @project.id).pluck(:id))
    end
    return unless params.key?(:issue_ids)
    ids = params[:issue_ids].to_s.scan(/\d+/).map(&:to_i).uniq
    @cr.set_links('issue', Issue.visible.where(id: ids, project_id: @project.self_and_descendants.pluck(:id)).pluck(:id))
  end

  # 승인하면 연결 요구사항 상태를 "변경"으로, 변경 이력에 CR 번호
  def mark_requirements
    return unless defined?(QaRequirement)
    @cr.requirements.each do |r|
      before = r.attributes.slice(*QaRequirement::TRACKED)
      r.status = 'changed' unless r.deleted?
      r.save!
      r.log_changes(User.current, before, [['cr', '', "#{@cr.code} #{@cr.title}"]])
    end
  end
end
