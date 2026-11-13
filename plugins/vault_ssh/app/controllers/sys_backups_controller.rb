# 프로젝트 > 운영 > 시스템 백업 — 백업 작업(DB 덤프 / 폴더) 등록 · [지금 백업] · 기록 · 덤프 받기 · 복원 안내
class SysBackupsController < ApplicationController
  menu_item :sys_backups

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_job, only: [:show, :edit, :update, :destroy, :run]
  before_action :find_run, only: [:download, :destroy_run]

  def index
    @jobs = SysBackupJob.where(project_id: @project.id).sorted.to_a
    @runs = SysBackupRun.where(project_id: @project.id).recent.includes(:sys_backup_job, :user).limit(30).to_a
    @ready = SshConsole::Backup.ready?
    @disk = SshConsole::Backup.disk
    @busy = @runs.any?(&:busy?)
  end

  def show
    @runs = @job.sys_backup_runs.includes(:user).to_a
    @busy = @runs.any?(&:busy?)
  end

  def new
    @job = SysBackupJob.new(project: @project, kind: params[:kind].presence_in(SysBackupJob::KINDS) || 'db', db_kind: 'mysql', schedule: 'daily', hour: 2, keep: 14)
    load_options
  end

  def create
    @job = SysBackupJob.new(project: @project, author_id: User.current.id)
    assign
    if save_job
      flash[:notice] = l(:notice_successful_create)
      redirect_to project_sys_backup_path(@project, @job)
    else
      load_options
      render :new
    end
  end

  def edit
    load_options
  end

  def update
    assign
    if save_job
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_sys_backup_path(@project, @job)
    else
      load_options
      render :edit
    end
  end

  def destroy
    @job.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_sys_backups_path(@project)
  end

  # [지금 백업] — 백그라운드
  def run
    if @job.busy?
      flash[:warning] = l(:notice_sb_busy)
    elsif !(key = @job.ssh_key) || !SshConsole::Access.can_connect?(User.current, key)
      flash[:error] = l(:error_sb_no_ssh)
    else
      r = SysBackupRun.create!(sys_backup_job: @job, project: @project, user: User.current, status: 'queued', trigger: 'manual')
      SshConsole::BackupJob.perform_later(r.id)
      flash[:notice] = l(:notice_sb_started)
    end
    redirect_to project_sys_backup_path(@project, @job)
  end

  # DB 덤프 받기 (.sql.gz)
  def download
    file = @run.path && Dir[@run.path.join('*.sql.gz').to_s].first
    return render_404 unless file && @run.status == 'done'
    Rails.logger.info("[sys_backup] download run #{@run.id} by #{User.current.login}")
    send_file file, filename: SshConsole::Backup.download_name(@run), type: 'application/gzip'
  end

  def destroy_run
    job = @run.sys_backup_job
    @run.destroy unless @run.busy?
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_sys_backup_path(@project, job)
  end

  private

  def find_job
    @job = SysBackupJob.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_run
    @run = SysBackupRun.find_by!(id: params[:run_id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # 고를 수 있는 접속정보 — SSH 서버(접속 권한 있는 것), 데이터베이스(볼 수 있는 비밀번호 유형, DB 이름 유형 먼저)
  def load_options
    keys = SshConsole::Access.visible_keys(User.current, @project)
    @ssh_keys = keys.select { |k| SshConsole::Target.ssh_key?(k) && SshConsole::Access.can_connect?(User.current, k) }
    @db_keys = keys.select { |k| k.is_a?(Vault::Password) && !SshConsole::Target.ssh_key?(k) }
                   .sort_by { |k| [k.vault_type&.name.to_s.match?(/데이터|DB/i) ? 0 : 1, k.name] }
  end

  def assign
    load_options
    p = params.require(:sys_backup_job).permit(:name, :vault_key_id, :kind, :db_kind, :db_host, :db_port, :db_name, :db_key_id, :dump_cmd,
                                                :paths, :excludes, :schedule, :hour, :weekday, :keep, :active)
    @job.assign_attributes(p.except(:vault_key_id, :db_key_id))
    @job.db_port = nil if p[:db_port].blank?
    @job.vault_key_id = @ssh_keys.find { |k| k.id == p[:vault_key_id].to_i }&.id
    @job.db_key_id = @db_keys.find { |k| k.id == p[:db_key_id].to_i }&.id
  end

  # 모델 검사 뒤에 접속정보 검사(권한 있는 것만 골랐는지)를 더해 저장
  def save_job
    ok = @job.valid?
    @job.errors.add(:vault_key_id, :blank) unless @job.vault_key_id
    @job.errors.add(:db_key_id, :blank) if @job.db? && @job.db_kind != 'custom' && @job.db_key_id.nil?
    ok && @job.errors.empty? && @job.save(validate: false)
  end
end
