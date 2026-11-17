# 프로젝트 > 운영 > 시스템 백업 — 폴더 백업본 [zip 받기]
# 보관 폴더(files/ 아래 원래 경로)를 zip 으로 만들면서 바로 내려보냄 (임시 파일·대기 없음)
# ActionController::Live: Redmine 이 넣은 Rack::ContentLength 가 본문 전체를 모으지 않고, 받는 쪽이 느리면 만드는 쪽도 기다림(메모리 일정)
# 이 컨트롤러만 Live(별도 스레드) — 나머지 시스템 백업 화면은 그대로
class SysBackupZipsController < ApplicationController
  include ActionController::Live
  menu_item :sys_backups

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_run

  def show
    job = @run.sys_backup_job
    return render_404 unless @run.status == 'done' && job.files? && SshConsole::Backup.zip_dir(@run)
    back = User.current.allowed_to?(:manage_sys_backups, @project) ? edit_project_sys_backup_path(@project, job) : project_sys_backup_path(@project, job)
    unless SshConsole::Backup.zip_ready?
      flash[:error] = l(:error_sb_zip_tool)
      return redirect_to(back)
    end
    if SshConsole::Backup.zip_busy?
      flash[:warning] = l(:notice_sb_zip_busy)
      return redirect_to(back)
    end
    Rails.logger.info("[sys_backup] zip run #{@run.id} by #{User.current.login}")
    name = SshConsole::Backup.zip_name(@run)
    ActiveRecord::Base.connection_pool.release_connection   # 오래 걸리므로 DB 연결은 돌려 둠
    response.headers['X-Accel-Buffering'] = 'no'            # 외부 nginx 가 모아 두지 않고 바로 넘기게
    response.headers['Cache-Control'] = 'no-cache, no-store'
    send_stream(filename: name, type: 'application/zip') do |stream|
      SshConsole::Backup.zip_each(@run) { |chunk| stream.write(chunk) }
    end
  rescue ActionController::Live::ClientDisconnected, IOError, Errno::EPIPE
    Rails.logger.info("[sys_backup] zip run #{@run&.id}: 받는 쪽이 끊음")
  end

  private

  def find_run
    @run = SysBackupRun.find_by!(id: params[:run_id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end
