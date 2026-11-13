# 오래된 접속 기록·녹화 지우기 (기본 365일) — cron: rake redmine:ssh_console:purge DAYS=365
namespace :redmine do
  namespace :ssh_console do
    desc 'Delete SSH session logs and recordings older than DAYS (default 365)'
    task purge: :environment do
      days = (ENV['DAYS'].presence || 365).to_i
      n = 0
      SshSession.where('created_at < ?', days.days.ago).find_each { |s| s.destroy; n += 1 }
      puts "ssh_console: #{n} old sessions removed (#{days} days)"
    end
  end
end
