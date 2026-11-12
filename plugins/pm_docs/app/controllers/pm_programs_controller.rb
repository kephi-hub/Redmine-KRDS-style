# 프로젝트 > 프로그램 목록 — 진척 KPI·개발자별, 메뉴에서 만들기, 저장소에서 소스 경로 추천, 엑셀 가져오기·내보내기
class PmProgramsController < ApplicationController
  menu_item :programs
  helper :pm_docs
  helper :qa_trace if Redmine::Plugin.installed?(:qa_trace)
  include PmDocsHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_program, only: [:show, :edit, :update, :destroy]

  def index
    all = PmProgram.where(project_id: @project.id).includes(:developer, :menu_item).sorted.to_a
    @kpi = PmProgram::STATUSES.to_h { |s| [s, all.count { |p| p.status == s }] }
    @kpi['all'] = all.size
    @kpi['nopath'] = all.count { |p| p.paths.empty? }
    @by_dev = all.group_by(&:developer).map { |u, l| [u, l.size, l.count { |p| %w(done tested).include?(p.status) }] }.sort_by { |u, _, _| u ? u.name : '~' }
    @status = params[:status].presence_in(PmProgram::STATUSES + ['nopath'])
    @kind = params[:kind].presence_in(PmProgram::KINDS)
    @dev = params[:developer_id].presence&.to_i
    @q = params[:q].to_s.strip
    list = all
    list = list.select { |p| @status == 'nopath' ? p.paths.empty? : p.status == @status } if @status
    list = list.select { |p| p.kind == @kind } if @kind
    list = list.select { |p| p.developer_id == @dev } if @dev
    list = list.select { |p| [p.code, p.name, p.source_paths, p.menu_item&.name].compact.any? { |v| v.downcase.include?(@q.downcase) } } if @q.present?
    @index = menus_on? ? MenuItem.where(project_id: @project.id).index_by(&:id) : {}
    # 메뉴(화면) 순서로 묶어 보여줌 — 메뉴 없는 프로그램은 끝에
    order = menus_on? ? MenuItem.ordered(@project).each_with_index.to_h { |(m, _), i| [m.id, i] } : {}
    @programs = list.sort_by { |p| [order[p.menu_item_id] || 1_000_000, p.code] }
    @grouped = menus_on? && @programs.any?(&:menu_item_id)
  end

  def show
    @index = menus_on? ? MenuItem.where(project_id: @project.id).index_by(&:id) : {}
    @cases = defined?(QaTestCase) && @project.module_enabled?(:qa_tests) ? QaTestCase.where(project_id: @project.id, pm_program_id: @program.id).sorted.to_a : []
    @latest = @cases.any? ? QaTrace::Trace.latest_results(@project) : {}
  end

  def new
    @program = PmProgram.new(project: @project, kind: 'screen', status: 'todo', menu_item_id: params[:menu_item_id])
    load_form
  end

  def create
    @program = PmProgram.new(program_params.merge(project: @project))
    if @program.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to params[:continue] ? new_project_pm_program_path(@project) : project_pm_program_path(@project, @program)
    else
      load_form
      render :new
    end
  end

  def edit
    load_form
  end

  def update
    if @program.update(program_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_pm_program_path(@project, @program)
    else
      load_form
      render :edit
    end
  end

  def destroy
    @program.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_pm_programs_path(@project)
  end

  # 메뉴 구조도에서 만들기 — 화면(화면 유형·화면 ID 가 있거나 말단, 사용 중인 것) 기준
  # mode=screen : 화면 1개 = 프로그램 1개 (프로그램이 이미 연결된 화면은 건너뜀, ID 는 화면 ID, 없으면 PGM-001…)
  # mode=function : 화면 유형별 기본 기능으로 펼침 (목록 → 조회·엑셀 다운로드, 등록·수정 → 등록·수정·삭제 …), ID 는 화면 ID-S/-I/-U/-D/-X
  #                 같은 ID 가 이미 있으면 건너뜀 → 다시 눌러도 빠진 것만 추가
  def from_menus
    return redirect_to(project_pm_programs_path(@project)) unless menus_on?
    ordered = MenuItem.ordered(@project)
    screens = MenuItem.screens(ordered).select(&:active?)
    index = ordered.to_h { |m, _| [m.id, m] }
    codes = PmProgram.where(project_id: @project.id).pluck(:code).map(&:upcase).to_set
    seq = PmProgram.where(project_id: @project.id).where('code LIKE ?', 'PGM-%').pluck(:code).map { |c| c[/\APGM-(\d+)/, 1].to_i }.max || 0
    n = 0
    PmProgram.transaction do
      if params[:mode] == 'function'
        screens.each do |m|
          base = m.screen_id.presence || PmProgram.where(project_id: @project.id, menu_item_id: m.id).pluck(:code).map { |c| c[/\A(PGM-\d+)/, 1] }.compact.first || format('PGM-%03d', seq += 1)
          PmProgram.default_funcs(m.screen_type).each do |action, label|
            code = "#{base}-#{PmProgram::SUFFIX[action]}"
            next if codes.include?(code.upcase)
            PmProgram.create!(project: @project, code: code, name: "#{m.name} : #{label}".truncate(150), kind: m.screen_type == 'popup' ? 'popup' : 'screen',
                              action_list: [action], menu_item_id: m.id, status: 'todo')
            codes << code.upcase
            n += 1
          end
        end
      else
        have = PmProgram.where(project_id: @project.id).pluck(:menu_item_id).compact.to_set
        screens.each do |m|
          next if have.include?(m.id)
          code = m.screen_id.presence
          code = nil if code && codes.include?(code.upcase)
          code ||= format('PGM-%03d', seq += 1)
          PmProgram.create!(project: @project, code: code, name: m.path(index).truncate(150), kind: m.screen_type == 'popup' ? 'popup' : 'screen',
                            action_list: PmProgram.default_funcs(m.screen_type).map(&:first), menu_item_id: m.id, status: 'todo')
          codes << code.upcase
          n += 1
        end
      end
    end
    flash[:notice] = l(:notice_pm_programs_created, count: n)
    redirect_to project_pm_programs_path(@project)
  end

  # 소스 경로 추천: GET 목록, POST 고른 것 반영 (paths[프로그램 id][] )
  def suggest
    if request.post?
      input = params[:paths].respond_to?(:to_unsafe_h) ? params[:paths].to_unsafe_h : {}
      n = 0
      PmProgram.where(project_id: @project.id, id: input.keys.map(&:to_i)).each do |p|
        add = Array(input[p.id.to_s]).map(&:to_s).reject(&:blank?)
        next if add.empty?
        p.update!(source_paths: (p.paths | add).join("\n"))
        n += 1
      end
      flash[:notice] = l(:notice_pm_paths_applied, count: n)
      return redirect_to(project_pm_programs_path(@project))
    end
    @suggestions = PmKit::Suggest.run(@project)
  end

  def export
    index = menus_on? ? MenuItem.where(project_id: @project.id).index_by(&:id) : {}
    send_data PmKit::Sheet.programs(PmProgram.where(project_id: @project.id).includes(:developer).sorted.to_a, index),
              filename: "프로그램목록_#{@project.identifier}_#{User.current.today.strftime('%Y%m%d')}.xlsx", type: PmKit::Sheet::XLSX
  end

  def import
    return unless request.post?
    file = params[:file]
    rows = file.respond_to?(:read) ? read_rows(file) : nil
    return import_error(l(:error_pm_bad_file)) if rows.blank?
    @result = PmKit::Importer.programs(@project, rows)
    return import_error(l(:error_pm_no_header)) unless @result
    flash.now[:notice] = l(:notice_pm_imported, created: @result[:created], updated: @result[:updated])
  end

  private

  def menus_on?
    defined?(MenuItem) && @project.module_enabled?(:menu_tree)
  end

  def find_program
    @program = PmProgram.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def program_params
    p = params.require(:pm_program).permit(:code, :name, :kind, :menu_item_id, :source_paths, :developer_id, :status, :planned_on, :done_on, :note, action_list: [])
    p[:developer_id] = nil unless @project.users.exists?(id: p[:developer_id])
    p[:menu_item_id] = nil unless menus_on? && MenuItem.exists?(id: p[:menu_item_id], project_id: @project.id)
    p
  end

  def load_form
    @ordered = menus_on? ? MenuItem.ordered(@project) : []
  end

  def read_rows(file)
    raw = file.read
    return KrdsUi::XlsxReader.read(raw) if raw.start_with?('PK')
    text = raw.dup.force_encoding('UTF-8').delete_prefix("﻿")
    text = raw.dup.force_encoding('CP949').encode('UTF-8', invalid: :replace, undef: :replace) unless text.valid_encoding?
    CSV.parse(text)
  rescue CSV::MalformedCSVError
    nil
  end

  def import_error(message)
    flash.now[:error] = message
    render :import
  end
end
