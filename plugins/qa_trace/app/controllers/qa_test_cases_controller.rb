# 프로젝트 > 테스트 > 케이스 — 목록, 메뉴별 현황, 등록·수정, 테스트 시나리오 엑셀 가져오기·내보내기
class QaTestCasesController < ApplicationController
  menu_item :qa_tests
  helper :qa_trace
  include QaTraceHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_case, only: [:show, :edit, :update, :destroy]

  def index
    @menus_on = QaTrace::Trace.menus_on?(@project)
    @index = @menus_on ? MenuItem.where(project_id: @project.id).index_by(&:id) : {}
    @latest = QaTrace::Trace.latest_results(@project)
    @kind = params[:kind].presence_in(QaTestCase::KINDS)
    @result = params[:result].presence_in(QaTestResult::RESULTS)
    @q = params[:q].to_s.strip
    scope = QaTestCase.where(project_id: @project.id)
    scope = scope.where(kind: @kind) if @kind
    scope = scope.where(active: true) unless params[:all] == '1'
    list = scope.sorted.to_a
    list = list.select { |c| (@latest[c.id]&.result || 'none') == @result } if @result
    if @q.present?
      q = @q.downcase
      list = list.select { |c| [c.code, c.name, @index[c.menu_item_id]&.path(@index), @index[c.menu_item_id]&.screen_id].compact.any? { |v| v.downcase.include?(q) } }
    end
    @cases = list
    @reqs = QaCaseRequirement.where(qa_test_case_id: list.map(&:id)).joins(:qa_requirement)
                             .pluck(:qa_test_case_id, 'qa_requirements.code').group_by(&:first).transform_values { |l| l.map(&:last).sort }
  end

  # 메뉴별 현황: 메뉴마다 케이스 수·최근 결과·연결 요구사항 수
  def menus
    @menus_on = QaTrace::Trace.menus_on?(@project)
    return unless @menus_on
    @ordered = MenuItem.ordered(@project)
    latest = QaTrace::Trace.latest_results(@project)
    cases = QaTestCase.where(project_id: @project.id).active.where.not(menu_item_id: nil).to_a
    @stats = cases.group_by(&:menu_item_id).transform_values do |l|
      res = l.map { |c| latest[c.id]&.result || 'none' }
      { total: l.size, pass: res.count('pass'), fail: res.count('fail'), none: res.count('none') }
    end
    @req_counts = QaRequirementMenu.joins(:qa_requirement).where(menu_item_id: @ordered.map { |m, _| m.id })
                                   .where.not(qa_requirements: { status: 'deleted' }).group(:menu_item_id).count
    leaves = @ordered.reject { |m, _| @ordered.any? { |x, _| x.parent_id == m.id } }
    @kpi = { screens: leaves.size, covered: leaves.count { |m, _| @stats[m.id] }, cases: cases.size,
             pass: @stats.values.sum { |s| s[:pass] }, fail: @stats.values.sum { |s| s[:fail] } }
  end

  def show
    @index = QaTrace::Trace.menus_on?(@project) ? MenuItem.where(project_id: @project.id).index_by(&:id) : {}
    @results = @case.qa_test_results.includes(:qa_test_run, :user, :issue).to_a.sort_by { |r| [r.qa_test_run.start_on || Date.new(1), r.qa_test_run_id] }.reverse
  end

  def new
    @case = QaTestCase.new(project: @project, kind: params[:kind].presence_in(QaTestCase::KINDS) || 'unit', menu_item_id: params[:menu_item_id])
    load_form
  end

  def create
    @case = QaTestCase.new(project: @project, author_id: User.current.id)
    @case.assign_attributes(case_params)
    QaTestCase.transaction do
      @case.save!
      save_reqs
    end
    flash[:notice] = l(:notice_successful_create)
    redirect_to params[:continue] ? new_project_qa_test_case_path(@project, kind: @case.kind, menu_item_id: @case.menu_item_id) : project_qa_test_case_path(@project, @case)
  rescue ActiveRecord::RecordInvalid
    load_form
    render :new
  end

  def edit
    load_form
  end

  def update
    @case.assign_attributes(case_params)
    QaTestCase.transaction do
      @case.save!
      save_reqs
    end
    flash[:notice] = l(:notice_successful_update)
    redirect_to project_qa_test_case_path(@project, @case)
  rescue ActiveRecord::RecordInvalid
    load_form
    render :edit
  end

  def destroy
    @case.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_qa_test_cases_path(@project)
  end

  def export
    cases = QaTestCase.where(project_id: @project.id).sorted.to_a
    send_data QaTrace::Sheet.export_cases(@project, cases, QaTrace::Trace.latest_results(@project)),
              filename: "테스트시나리오_#{@project.identifier}_#{User.current.today.strftime('%Y%m%d')}.xlsx", type: QaTrace::Sheet::XLSX
  end

  def import
    return unless request.post?
    file = params[:file]
    return import_error(l(:error_qa_no_file)) unless file.respond_to?(:read)
    rows = QaTrace::Sheet.read_file(file)
    return import_error(l(:error_qa_bad_file)) if rows.blank?
    @result = QaTrace::Sheet.import_cases(@project, rows, User.current)
    return import_error(l(:error_qa_no_header_case)) unless @result
    flash.now[:notice] = l(:notice_qa_imported, created: @result[:created], updated: @result[:updated])
  end

  private

  def find_case
    @case = QaTestCase.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def case_params
    p = params.require(:qa_test_case).permit(:code, :kind, :menu_item_id, :name, :precondition, :steps, :expected, :active)
    p[:menu_item_id] = nil unless QaTrace::Trace.menus_on?(@project) && MenuItem.exists?(id: p[:menu_item_id], project_id: @project.id)
    p
  end

  def import_error(message)
    flash.now[:error] = message
    render :import
  end

  def load_form
    @menus_on = QaTrace::Trace.menus_on?(@project)
    @ordered = @menus_on ? MenuItem.ordered(@project) : []
    @reqs_on = @project.module_enabled?(:qa_requirements)
    @all_reqs = @reqs_on ? QaRequirement.where(project_id: @project.id).alive.to_a.sort_by { |r| [QaRequirement.category_order(r.category), r.code] } : []
  end

  def save_reqs
    return unless params[:reqs_sent] == '1' && @project.module_enabled?(:qa_requirements)
    ids = Array(params[:qa_requirement_ids]).map(&:to_i) & QaRequirement.where(project_id: @project.id).pluck(:id)
    @case.qa_requirement_ids = ids.uniq
  end
end
