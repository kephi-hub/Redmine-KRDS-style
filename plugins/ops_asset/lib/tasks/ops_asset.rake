namespace :redmine do
  namespace :ops_asset do
    desc '자산 만료 알림 메일 (만료 30·7·1일 전·당일·다음 날). DRY_RUN=1 이면 보내지 않고 대상만'
    task notify: :environment do
      r = OpsKit::Notifier.run(Date.current, dry_run: ENV['DRY_RUN'] == '1')
      puts "알림 대상 자산 #{r[:due]}건 · 받는 사람 #{r[:users]}명 · 보낸 메일 #{r[:sent]}통#{' (메일 발송 꺼짐)' unless r[:deliveries]}"
    end

    desc '서버 자산 정보 수집(SSH 접속정보 연결된 서버) + 인증서·도메인 자산 HTTPS 인증서 확인'
    task probe: :environment do
      ok = ng = 0
      OpsAsset.where(active: true, kind: 'server').where.not(vault_key_id: nil).find_each { |a| OpsKit::Probe.server(a)[:ok] ? ok += 1 : ng += 1 }
      cok = cng = 0
      OpsAsset.where(active: true, kind: %w(cert domain)).where.not(address: [nil, '']).find_each { |a| OpsKit::Probe.cert(a)[:ok] ? cok += 1 : cng += 1 }
      warn = OpsAsset.where(active: true).where('disk_pct >= ?', OpsKit::Probe::DISK_WARN).count
      puts "서버 정보 #{ok}건 수집(실패 #{ng}) · 디스크 #{OpsKit::Probe::DISK_WARN}% 이상 #{warn}건 · 인증서 #{cok}건 확인(실패 #{cng})"
    end
  end
end
