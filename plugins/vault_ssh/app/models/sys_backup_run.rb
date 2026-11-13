# 시스템 백업 한 번 — 상태 · 받은 양 · 파일 수(새로 받음 / 지난번과 같아 연결) · 보관 폴더
class SysBackupRun < ApplicationRecord
  belongs_to :sys_backup_job
  belongs_to :project
  belongs_to :user, optional: true

  scope :recent, -> { order(id: :desc) }

  def path
    dir.present? ? SshConsole::Backup.root.join(dir) : nil
  end

  def busy?
    %w(queued running).include?(status)
  end

  def seconds
    started_at && ((finished_at || Time.current) - started_at).to_i
  end

  # 보관 폴더도 같이 지움
  after_destroy { FileUtils.rm_rf(path) if path && path.to_s.start_with?(SshConsole::Backup.root.to_s) }
end
