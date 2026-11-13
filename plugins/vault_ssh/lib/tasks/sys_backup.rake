# 프로젝트 시스템 백업 일정 실행 — cron 이 매시간 부름 (그 시각이 일정인 작업만, 하나씩 차례로)
namespace :redmine do
  namespace :sys_backup do
    desc 'Run scheduled project system backups that are due this hour'
    task run: :environment do
      now = Time.current.in_time_zone('Asia/Seoul')
      due = SysBackupJob.where(active: true).where.not(schedule: 'off').select { |j| j.due?(now) && !j.busy? }
      due.each do |j|
        r = SysBackupRun.create!(sys_backup_job: j, project_id: j.project_id, status: 'queued', trigger: 'schedule')
        SshConsole::Backup.run!(r)
        r.reload
        puts "#{now.strftime('%F %R')} #{j.project&.identifier}/#{j.name}: #{r.status} #{r.bytes}B #{r.error}"
      end
      puts "#{now.strftime('%F %R')} sys_backup: due #{due.size}" if due.empty?
    end
  end
end
