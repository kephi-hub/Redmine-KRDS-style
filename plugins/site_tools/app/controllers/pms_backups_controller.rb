# 관리 > 백업 — PMS 백업(DB · 첨부파일 · Vault 키) 목록·상태, [지금 백업] 요청 (실제 백업은 서버 setup/backup.sh)
class PmsBackupsController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :pms_backups

  before_action :require_admin

  def index
    @status = SiteTools::Backup.status
    @list = SiteTools::Backup.list
    @running = SiteTools::Backup.running_since
    @requested = SiteTools::Backup.requested?
  end

  def create
    if !SiteTools::Backup.writable?
      flash[:error] = l(:error_pms_backup_not_ready)
    elsif SiteTools::Backup.running_since || SiteTools::Backup.requested?
      flash[:warning] = l(:notice_pms_backup_busy)
    else
      SiteTools::Backup.request!(User.current)
      flash[:notice] = l(:notice_pms_backup_requested)
    end
    redirect_to pms_backups_path
  end
end
