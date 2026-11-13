# 프로젝트 > DB > 이관 — 원본 → 대상 (MariaDB·MySQL), 테이블마다 건너뜀/구조만/구조+데이터, 미리보기 → 실행 → 결과·백업
class DbMigrationsController < ApplicationController
  menu_item :db_schemas
  helper :db_schemas

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :load_links
  before_action :find_migration, only: [:show, :backup]

  def index
    @migrations = DbMigration.where(project_id: @project.id).recent.limit(20).to_a
    return if @links.size < 2
    pick_links
    return unless @source && @target && @source != @target
    return @unsupported = true unless DbManage::Migrator.supported?(@source, @target)
    sa = snapshot(@source)
    sb = sa && snapshot(@target)
    return unless sa && sb
    cmp = DbManage::Analysis.compare(sa, sb)
    status = {}
    cmp[:only_a].each { |t| status[t[:name]] = 'new' }
    cmp[:changed].each { |c| status[c[:table]] = 'changed' }
    @tables = sa[:tables].reject { |t| t[:view] }.map { |t| t.merge(status: status[t[:name]] || 'same') }
    @only_target = cmp[:only_b].reject { |t| t[:view] }.map { |t| t[:name] }
    @busy = DbMigration.where(project_id: @project.id, target_link_id: @target.id, status: %w(queued running)).where('created_at > ?', 6.hours.ago).exists?
  end

  def preview
    pick_links
    return unless check_pair
    @choices = choices
    return redirect_with(:error, l(:error_db_mig_none)) if @choices.empty?
    @plan = DbManage::Migrator.preview(@source, @target, @choices)
    @sql = sql_text(@plan)
  rescue DbManage::Error => e
    redirect_with(:error, e.message)
  end

  def create
    pick_links
    return unless check_pair
    list = choices
    return redirect_with(:error, l(:error_db_mig_none)) if list.empty?
    if @target.production?
      return redirect_with(:error, l(:error_db_mig_confirm)) unless params[:confirm].to_s.strip == @project.identifier && params[:reason].to_s.strip.present?
    end
    if DbMigration.where(project_id: @project.id, target_link_id: @target.id, status: %w(queued running)).where('created_at > ?', 6.hours.ago).exists?
      return redirect_with(:warning, l(:notice_db_mig_busy))
    end
    mig = DbMigration.create!(project: @project, user: User.current, source_link_id: @source.id, target_link_id: @target.id,
                              source_name: @source.name, target_name: @target.name, target_production: @target.production?,
                              status: 'queued', plan: list.to_json, results: [], reason: params[:reason].to_s.strip.truncate(255).presence)
    Rails.logger.info("[db_migrate] #{mig.id} #{@source.name} -> #{@target.name} by #{User.current.login}: #{list.size} tables")
    DbManage::MigrateJob.perform_later(mig.id)
    flash[:notice] = l(:notice_db_mig_started)
    redirect_to project_db_migration_path(@project, mig)
  end

  def show
    @results = @mig.result_list
  end

  # 이관 전 대상 테이블 백업 (.sql.gz)
  def backup
    name = File.basename(params[:file].to_s)
    file = @mig.backup_dir.join(name)
    return render_404 if @mig.backup_removed || !name.end_with?('.sql.gz') || !File.file?(file)
    Rails.logger.info("[db_migrate] backup download #{@mig.id}/#{name} by #{User.current.login}")
    send_file file, filename: "#{@project.identifier}_mig#{@mig.id}_#{name}", type: 'application/gzip'
  end

  private

  def load_links
    @links = @project.db_links.includes(:db_server).sorted.to_a
  end

  def find_migration
    @mig = DbMigration.find_by(id: params[:id], project_id: @project.id) or render_404
  end

  # 기본: 개발 → 운영
  def pick_links
    @source = @links.find { |l| l.id.to_s == params[:source].to_s } || @links.find { |l| !l.production? } || @links.first
    @target = @links.find { |l| l.id.to_s == params[:target].to_s } || (@links - [@source]).find(&:production?) || (@links - [@source]).first
  end

  def can_target?(link)
    User.current.allowed_to?(link.production? ? :migrate_db_production : :migrate_db, @project)
  end
  helper_method :can_target?

  def check_pair
    unless @source && @target && DbManage::Migrator.supported?(@source, @target)
      redirect_with(:error, l(:error_db_mig_pair))
      return false
    end
    unless can_target?(@target)
      deny_access
      return false
    end
    true
  end

  # mode[테이블] = skip|structure|replace|upsert|insert_new (원본 표시 순서대로)
  def choices
    raw = params[:mode].respond_to?(:to_unsafe_h) ? params[:mode].to_unsafe_h : (params[:mode] || {})
    raw.filter_map do |table, mode|
      next unless DbManage::Migrator::MODES.include?(mode) && mode != 'skip' && table.to_s.length <= 128
      { 'table' => table.to_s, 'mode' => mode }
    end
  end

  def redirect_with(kind, message)
    flash[kind] = message
    redirect_to project_db_migrations_path(@project, source: @source&.id, target: @target&.id)
  end

  def sql_text(plan)
    out = +"-- #{@source.name} → #{@target.name} 이관 미리보기 (#{Time.current.in_time_zone('Asia/Seoul').strftime('%F %R')})\n-- 대상 DB 세션: SET FOREIGN_KEY_CHECKS = 0\n\n"
    plan.each do |p|
      out << "-- [#{p[:table]}] #{l("label_db_mig_mode_#{p[:mode]}")}\n"
      (p[:statements] || []).each { |s| out << "#{s};\n" }
      out << "-- 데이터: #{l("label_db_mig_mode_#{p[:mode]}")} (실행 때 원본에서 읽어 INSERT)\n" if DbManage::Migrator::DATA_MODES.include?(p[:mode])
      out << "\n"
    end
    out
  end

  def snapshot(link)
    key = ['db_manage', 'snapshot', link.id, link.db_server.id, link.db_server.updated_at.to_i, link.schema].join('/')
    Rails.cache.delete(key) if params[:refresh] == '1'
    Rails.cache.fetch(key, expires_in: 10.minutes) { link.connector.snapshot(objects: true) }
  rescue DbManage::Error => e
    @db_error = "#{link.name}: #{e.message}"
    nil
  end
end
