# 프로젝트 > 요구사항 — 목록(KPI·필터), 추적표, 상세(연결·변경 이력), 등록·수정, 엑셀 가져오기·내보내기
class QaRequirementsController < ApplicationController
  menu_item :qa_requirements
  helper :qa_trace
  include QaTraceHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_req, only: [:show, :edit, :update, :destroy]

  RISKS = %w(no_menu no_test fail pass deleted_open).freeze

  def index
    load_list
  end

  def trace
    load_list
  end

  def show
    @info = QaTrace::Trace.build(@project, [@req])[@req.id]
    @children = @req.children.sorted.to_a
    @logs = @req.qa_requirement_logs.includes(:user).limit(100).to_a
  end

  def new
    @req = QaRequirement.new(project: @project, category: params[:category].presence_in(QaRequirement::CATEGORIES) || 'SFR',
                             parent_id: params[:parent_id])
    load_form
  end

  def create
    @req = QaRequirement.new(project: @project, author_id: User.current.id)
    @req.assign_attributes(req_params)
    QaRequirement.transaction do
      @req.save!
      save_links
      QaRequirementLog.create!(qa_requirement_id: @req.id, user_id: User.current.id, details: [['_create', nil, @req.code]].to_json)
    end
    flash[:notice] = l(:notice_successful_create)
    redirect_to params[:continue] ? new_project_qa_requirement_path(@project, category: @req.category) : project_qa_requirement_path(@project, @req)
  rescue ActiveRecord::RecordInvalid
    load_form
    render :new
  end

  def edit
    load_form
  end

  def update
    before = @req.attributes.slice(*QaRequirement::TRACKED)
    @req.assign_attributes(req_params)
    QaRequirement.transaction do
      @req.save!
      @req.log_changes(User.current, before, save_links)
    end
    flash[:notice] = l(:notice_successful_update)
    redirect_to project_qa_requirement_path(@project, @req)
  rescue ActiveRecord::RecordInvalid
    load_form
    render :edit
  end

  def destroy
    @req.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_qa_requirements_path(@project)
  end

  def export
    reqs = sorted(QaRequirement.where(project_id: @project.id).to_a)
    info = QaTrace::Trace.build(@project, reqs)
    send_data QaTrace::Sheet.export_requirements(@project, reqs, info),
              filename: "요구사항_#{@project.identifier}_#{User.current.today.strftime('%Y%m%d')}.xlsx", type: QaTrace::Sheet::XLSX
  end

  def import
    return unless request.post?
    file = params[:file]
    return import_error(l(:error_qa_no_file)) unless file.respond_to?(:read)
    rows = QaTrace::Sheet.read_file(file)
    return import_error(l(:error_qa_bad_file)) if rows.blank?
    @result = QaTrace::Sheet.import_requirements(@project, rows, User.current)
    return import_error(l(:error_qa_no_header_req)) unless @result
    flash.now[:notice] = l(:notice_qa_imported, created: @result[:created], updated: @result[:updated])
  end

  private

  def find_req
    @req = QaRequirement.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def req_params
    params.require(:qa_requirement).permit(:code, :category, :name, :description, :source, :priority, :status, :parent_id)
  end

  def import_error(message)
    flash.now[:error] = message
    render :import
  end

  def sorted(list)
    list.sort_by { |r| [QaRequirement.category_order(r.category), r.code] }
  end

  def load_list
    all = sorted(QaRequirement.where(project_id: @project.id).to_a)
    @info = QaTrace::Trace.build(@project, all)
    alive = all.reject(&:deleted?)
    @kpi = {
      'all' => alive.size,
      'confirmed' => alive.count { |r| r.status == 'confirmed' },
      'no_menu' => alive.count { |r| @info[r.id][:risks].include?('no_menu') },
      'no_test' => alive.count { |r| @info[r.id][:risks].include?('no_test') },
      'fail' => alive.count { |r| @info[r.id][:risks].include?('fail') },
      'pass' => alive.count { |r| @info[r.id][:state] == 'pass' },
      'deleted_open' => all.count { |r| @info[r.id][:risks].include?('deleted_open') }
    }
    @menus_on = QaTrace::Trace.menus_on?(@project)
    @category = params[:category].presence_in(QaRequirement::CATEGORIES)
    @status = params[:status].presence_in(QaRequirement::STATUSES + ['all'])
    @risk = params[:risk].presence_in(RISKS)
    @q = params[:q].to_s.strip
    list = all
    list = list.reject(&:deleted?) unless @status || @risk == 'deleted_open'
    list = list.select { |r| r.status == @status } if @status && @status != 'all'
    list = list.select { |r| r.category == @category } if @category
    if @risk == 'pass'
      list = list.select { |r| @info[r.id][:state] == 'pass' }
    elsif @risk
      list = list.select { |r| @info[r.id][:risks].include?(@risk) }
    end
    if @q.present?
      q = @q.downcase
      list = list.select { |r| [r.code, r.name, r.description, r.source].compact.any? { |v| v.downcase.include?(q) } }
    end
    @reqs = list
  end

  def load_form
    @menus_on = QaTrace::Trace.menus_on?(@project)
    @ordered = @menus_on ? MenuItem.ordered(@project) : []
    @parents = sorted(QaRequirement.where(project_id: @project.id).where.not(id: @req.id).to_a)
  end

  # 메뉴(선택칸을 보낸 경우만)·일감 번호 저장 → 변경 이력용 [[칸, 이전, 이후]]
  def save_links
    extra = []
    if params[:menus_sent] == '1' && QaTrace::Trace.menus_on?(@project)
      index = MenuItem.where(project_id: @project.id).index_by(&:id)
      wanted = Array(params[:menu_item_ids]).map(&:to_i).uniq.select { |i| index[i] }
      old = @req.menu_item_ids
      if wanted.sort != old.sort
        @req.menu_item_ids = wanted
        extra << ['menus', old.map { |i| index[i]&.name }.compact.join(', '), wanted.map { |i| index[i].name }.join(', ')]
      end
    end
    if params.key?(:issue_ids)
      ids = params[:issue_ids].to_s.scan(/\d+/).map(&:to_i).uniq
      found = Issue.visible.where(id: ids, project_id: @project.self_and_descendants.pluck(:id)).pluck(:id)
      missing = ids - found
      flash[:warning] = l(:warning_qa_issue_missing, ids: missing.map { |i| "##{i}" }.join(', ')) if missing.any?
      old = @req.issue_ids
      if found.sort != old.sort
        @req.issue_ids = found
        extra << ['issues', old.sort.map { |i| "##{i}" }.join(', '), found.sort.map { |i| "##{i}" }.join(', ')]
      end
    end
    extra
  end
end
