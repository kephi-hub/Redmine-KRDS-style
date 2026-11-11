# 프로젝트 > 테스트 > 회차 — 회차 목록·진행률, 결과 입력(한 화면에서 여러 줄), 불합격 → 결함 일감, 테스트 결과서 엑셀
class QaTestRunsController < ApplicationController
  menu_item :qa_tests
  helper :qa_trace
  include QaTraceHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_run, except: [:index, :new, :create]

  def index
    @runs = QaTestRun.where(project_id: @project.id).sorted.to_a
  end

  def new
    @run = QaTestRun.new(project: @project, start_on: User.current.today)
  end

  def create
    @run = QaTestRun.new(run_params.merge(project: @project, author_id: User.current.id))
    if @run.save
      added = @run.sync_cases
      flash[:notice] = l(:notice_qa_run_created, count: added)
      redirect_to project_qa_test_run_path(@project, @run)
    else
      render :new
    end
  end

  def show
    load_results
  end

  def edit
  end

  def update
    if @run.update(run_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_qa_test_run_path(@project, @run)
    else
      render :edit
    end
  end

  def destroy
    @run.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_qa_test_runs_path(@project)
  end

  # 결과 저장: r[결과 id][result|note]
  def save
    return closed_error unless @run.open?
    changed = save_results
    flash[:notice] = l(:notice_qa_results_saved, count: changed)
    redirect_to project_qa_test_run_path(@project, @run, back_params)
  end

  # 결과를 먼저 저장하고 고른 줄(불합격)로 결함 일감 만들기
  def defect
    return closed_error unless @run.open?
    save_results
    result = @run.qa_test_results.includes(:qa_test_case).find_by(id: params[:result_id])
    return render_404 unless result
    unless User.current.allowed_to?(:add_issues, @project)
      flash[:error] = l(:notice_not_authorized)
      return redirect_to(project_qa_test_run_path(@project, @run, back_params))
    end
    if result.issue_id && result.issue && !result.issue.closed?
      flash[:warning] = l(:warning_qa_defect_exists, id: result.issue_id)
      return redirect_to(project_qa_test_run_path(@project, @run, back_params))
    end
    issue = build_defect(result)
    if issue.save
      result.update!(issue_id: issue.id, result: 'fail', user_id: result.user_id || User.current.id, tested_at: result.tested_at || Time.current)
      if issue.respond_to?(:menu_items) && result.qa_test_case.menu_item_id && @project.module_enabled?(:menu_tree)
        MenuItemIssue.find_or_create_by!(menu_item_id: result.qa_test_case.menu_item_id, issue_id: issue.id)
      end
      flash[:notice] = l(:notice_qa_defect_created, id: issue.id)
    else
      flash[:error] = issue.errors.full_messages.join(', ')
    end
    redirect_to project_qa_test_run_path(@project, @run, back_params.merge(focus: result.id))
  end

  # 대상 케이스 맞추기 (회차를 만든 뒤 추가된 케이스)
  def sync
    added = @run.sync_cases
    flash[:notice] = l(:notice_qa_run_synced, count: added)
    redirect_to project_qa_test_run_path(@project, @run)
  end

  def export
    load_results(all: true)
    send_data QaTrace::Sheet.export_run(@project, @run, @results),
              filename: "테스트결과서_#{@project.identifier}_#{@run.name.gsub(/[\\\/:*?"<>|\s]+/, '_')}.xlsx", type: QaTrace::Sheet::XLSX
  end

  private

  def find_run
    @run = QaTestRun.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def run_params
    params.require(:qa_test_run).permit(:name, :kind, :start_on, :end_on, :status, :note)
  end

  def back_params
    { result: params[:filter_result].presence, q: params[:filter_q].presence }.compact
  end

  def closed_error
    flash[:error] = l(:error_qa_run_closed)
    redirect_to project_qa_test_run_path(@project, @run)
  end

  def load_results(all: false)
    @menus_on = QaTrace::Trace.menus_on?(@project)
    @index = @menus_on ? MenuItem.where(project_id: @project.id).index_by(&:id) : {}
    order = @menus_on ? MenuItem.ordered(@project).each_with_index.to_h { |(m, _), i| [m.id, i] } : {}
    results = @run.qa_test_results.includes(:qa_test_case, :user, issue: :status).to_a
    results.sort_by! { |r| [order[r.qa_test_case.menu_item_id] || 99_999, r.qa_test_case.code] }
    @counts = results.group_by(&:result).transform_values(&:size)
    @retest = results.count(&:retest?)
    @all_count = results.size
    unless all
      @filter = params[:result].presence_in(QaTestResult::RESULTS + ['retest'])
      @q = params[:q].to_s.strip
      results = results.select { |r| @filter == 'retest' ? r.retest? : r.result == @filter } if @filter
      if @q.present?
        q = @q.downcase
        results = results.select { |r| [r.qa_test_case.code, r.qa_test_case.name, @index[r.qa_test_case.menu_item_id]&.path(@index)].compact.any? { |v| v.downcase.include?(q) } }
      end
      @trackers = @project.trackers.to_a
      @tracker = @trackers.find { |t| t.name == '결함' } || @trackers.find { |t| t.name =~ /bug|버그|오류/i } || @trackers.first
    end
    @results = results
  end

  def save_results
    input = params[:r].respond_to?(:to_unsafe_h) ? params[:r].to_unsafe_h : {}
    return 0 if input.empty?
    changed = 0
    results = @run.qa_test_results.where(id: input.keys.map(&:to_i)).index_by(&:id)
    QaTestResult.transaction do
      input.each do |rid, v|
        r = results[rid.to_i]
        next unless r && v.respond_to?(:[])
        res = v['result'].to_s.presence_in(QaTestResult::RESULTS) || r.result
        note = v['note'].to_s.strip.presence
        next if res == r.result && note == r.note
        if res != r.result
          r.result = res
          r.user_id = res == 'none' ? nil : User.current.id
          r.tested_at = res == 'none' ? nil : Time.current
        end
        r.note = note
        r.save!
        changed += 1
      end
    end
    changed
  end

  def build_defect(result)
    c = result.qa_test_case
    tracker = @project.trackers.find_by(id: params[:tracker_id]) || @project.trackers.find_by(name: '결함') || @project.trackers.first
    index = @project.module_enabled?(:menu_tree) ? MenuItem.where(project_id: @project.id).index_by(&:id) : {}
    menu = index[c.menu_item_id]
    lines = ["테스트 회차: #{@run.name}", "테스트 케이스: #{c.code} #{c.name}"]
    lines << "화면: #{menu.path(index)}#{" (#{menu.screen_id})" if menu&.screen_id}" if menu
    { '사전조건' => c.precondition, '절차' => c.steps, '기대결과' => c.expected, '실제 결과' => result.note }.each do |k, v|
      lines += ['', "■ #{k}", v.presence || '-']
    end
    issue = Issue.new(project: @project, author: User.current)
    issue.tracker = tracker
    issue.status = tracker&.default_status
    issue.priority = IssuePriority.default || IssuePriority.active.first
    issue.subject = "[#{c.code}] #{c.name} — 테스트 불합격".truncate(255)
    issue.description = lines.join("\n")
    issue
  end
end
