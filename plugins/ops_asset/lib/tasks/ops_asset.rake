namespace :redmine do
  namespace :ops_asset do
    desc '자산 만료 알림 메일 (만료 30·7·1일 전·당일·다음 날). DRY_RUN=1 이면 보내지 않고 대상만'
    task notify: :environment do
      r = OpsKit::Notifier.run(Date.current, dry_run: ENV['DRY_RUN'] == '1')
      puts "알림 대상 자산 #{r[:due]}건 · 받는 사람 #{r[:users]}명 · 보낸 메일 #{r[:sent]}통#{' (메일 발송 꺼짐)' unless r[:deliveries]}"
    end
  end
end
