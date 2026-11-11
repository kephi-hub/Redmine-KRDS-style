# 용어사전 — 프로젝트 용어사전(/projects/:id/glossary)과 전사 공통 용어사전(/glossary, 관리자 전용)을 함께 처리
require 'csv'

class GlossaryTermsController < ApplicationController
  helper :glossary
  layout :glossary_layout

  before_action :find_optional_project_by_project_id
  before_action :check_access
  before_action :find_term, only: [:edit, :update, :destroy]

  PER_PAGE = 50
  # CSV 머리줄 (한글·영문 모두 받음)
  CSV_HEADERS = {
    'name' => %w(용어 용어명 name), 'name_en' => %w(영문명 영문 name_en english), 'abbr' => %w(약어 영문약어 컬럼명 abbr),
    'category' => %w(분류 category), 'data_type' => %w(데이터타입 데이터\ 타입 타입 data_type type),
    'data_length' => %w(길이 data_length length), 'definition' => %w(정의 설명 definition), 'note' => %w(비고 note)
  }.freeze

  def index
    scope = base_scope
    @q = params[:q].to_s.strip.presence
    if @q
      like = "%#{GlossaryTerm.sanitize_sql_like(@q.downcase)}%"
      scope = scope.where('LOWER(name) LIKE :q OR LOWER(name_en) LIKE :q OR LOWER(abbr) LIKE :q OR LOWER(definition) LIKE :q', q: like)
    end
    @category = params[:category].to_s.presence
    scope = scope.where(category: @category) if @category
    @scope_filter = %w(project common).include?(params[:scope]) && @project ? params[:scope] : nil
    scope = @scope_filter == 'common' ? scope.common : scope.where(project_id: @project.id) if @scope_filter
    @categories = base_scope.where.not(category: [nil, '']).distinct.order(:category).pluck(:category)
    @term_count = scope.count
    @term_pages = Redmine::Pagination::Paginator.new(@term_count, PER_PAGE, params['page'])
    @terms = scope.sorted.includes(:project).limit(PER_PAGE).offset(@term_pages.offset).to_a
  end

  def new
    @term = GlossaryTerm.new(project: @project)
  end

  def create
    @term = GlossaryTerm.new(project: @project, author: User.current, updated_by: User.current)
    @term.safe_attributes = params[:glossary_term]
    if @term.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to list_path
    else
      render :new
    end
  end

  def edit
  end

  def update
    @term.safe_attributes = params[:glossary_term]
    @term.updated_by = User.current
    if @term.save
      flash[:notice] = l(:notice_successful_update)
      redirect_to list_path
    else
      render :edit
    end
  end

  def destroy
    @term.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to list_path
  end

  # 엑셀에서 바로 열리도록 UTF-8 BOM 을 붙인 CSV
  def export
    terms = base_scope.sorted.includes(:project).to_a
    data = CSV.generate do |csv|
      csv << %w(용어 영문명 약어 분류 데이터타입 길이 정의 비고 구분)
      terms.each { |t| csv << [t.name, t.name_en, t.abbr, t.category, t.data_type, t.data_length, t.definition, t.note, t.common? ? '공통' : t.project&.name] }
    end
    name = @project ? "용어사전_#{@project.identifier}" : '공통_용어사전'
    send_data("﻿" + data, type: 'text/csv; charset=utf-8', filename: "#{name}_#{User.current.today.strftime('%Y%m%d')}.csv")
  end

  # GET: 가져오기 화면, POST: CSV 반영 (같은 이름이 있으면 덮어쓰기 선택)
  def import
    return unless request.post?
    file = params[:file]
    return import_error(l(:error_glossary_no_file)) unless file.respond_to?(:read)
    rows = parse_csv(file.read)
    return import_error(l(:error_glossary_bad_csv)) unless rows
    overwrite = params[:overwrite] == '1'
    @result = { created: 0, updated: 0, skipped: 0, errors: [] }
    GlossaryTerm.transaction do
      rows.each_with_index do |attrs, i|
        line = i + 2
        next @result[:errors] << [line, l(:error_glossary_no_name)] if attrs['name'].blank?
        term = GlossaryTerm.where(project_id: @project&.id).where('LOWER(name) = ?', attrs['name'].strip.downcase).first
        if term && !overwrite
          @result[:skipped] += 1
          next
        end
        term ||= GlossaryTerm.new(project: @project, author: User.current)
        created = term.new_record?
        term.attributes = attrs.slice(*GlossaryTerm::COLUMNS).transform_values { |v| v.to_s.strip.presence }
        term.updated_by = User.current
        if term.save
          created ? @result[:created] += 1 : @result[:updated] += 1
        else
          @result[:errors] << [line, "#{attrs['name']}: #{term.errors.full_messages.join(', ')}"]
        end
      end
    end
    flash.now[:notice] = l(:notice_glossary_imported, created: @result[:created], updated: @result[:updated], skipped: @result[:skipped])
  end

  # 프로젝트 화면은 용어사전 탭, 관리 화면은 공통 용어사전 메뉴를 강조
  # (메뉴 도우미가 호출하므로 public)
  def current_menu_item
    @project ? :glossary : :glossary_common
  end

  private

  def find_optional_project_by_project_id
    @project = Project.find(params[:project_id]) if params[:project_id].present?
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def glossary_layout
    @project ? 'base' : 'admin'
  end

  # 프로젝트: 보기는 view_glossary, 등록·수정·삭제·가져오기는 manage_glossary. 공통 용어사전은 관리자만
  def check_access
    if @project.nil?
      require_admin
    else
      action = %w(index export).include?(action_name) ? :view_glossary : :manage_glossary
      deny_access unless User.current.allowed_to?(action, @project)
    end
  end

  def base_scope
    @project ? GlossaryTerm.for_project(@project) : GlossaryTerm.common
  end

  # 공통 용어는 관리자만, 프로젝트 용어는 그 프로젝트에서만 수정
  def find_term
    @term = GlossaryTerm.find(params[:id])
    allowed = @term.common? ? User.current.admin? : (@project && @term.project_id == @project.id)
    deny_access unless allowed
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def list_path
    @project ? project_glossary_terms_path(@project) : glossary_terms_path
  end
  helper_method :list_path

  def import_error(message)
    flash.now[:error] = message
    render :import
  end

  # 엑셀 CSV 는 한글 Windows(CP949) 로 저장되는 경우가 많아 UTF-8 이 아니면 변환
  def parse_csv(raw)
    text = raw.to_s.dup.force_encoding('UTF-8').delete_prefix("﻿")
    text = raw.to_s.dup.force_encoding('CP949').encode('UTF-8', invalid: :replace, undef: :replace) unless text.valid_encoding?
    table = CSV.parse(text, headers: true)
    map = table.headers.compact.each_with_object({}) do |h, m|
      key = CSV_HEADERS.find { |_, names| names.include?(h.to_s.strip.downcase.delete(' ')) || names.include?(h.to_s.strip) }&.first
      m[h] = key if key
    end
    return nil unless map.value?('name')
    table.map { |row| map.each_with_object({}) { |(h, key), a| a[key] = row[h] } }
  rescue CSV::MalformedCSVError, Encoding::Error
    nil
  end
end
