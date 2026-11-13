# 시스템 백업 [지금 백업] — 백그라운드(같은 프로세스의 ActiveJob)
module SshConsole
  class BackupJob < ActiveJob::Base
    queue_as :default

    def perform(run_id)
      run = SysBackupRun.find_by(id: run_id)
      Backup.run!(run) if run&.status == 'queued'
    end
  end
end
