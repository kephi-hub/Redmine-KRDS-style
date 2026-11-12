namespace :redmine do
  namespace :menu_tree do
    desc '화면 캡처 예약 실행 — 캡처 설정의 일정이 매일 · 매주(월요일)인 것 (setup/cron.example)'
    task capture: :environment do
      runs = MenuTree::Capture.run_scheduled
      runs.each { |r| puts "#{r.project.identifier} #{r.menu_capture_config&.label}: #{r.status} 화면 #{r.total} · 성공 #{r.ok} · 실패 #{r.failed} · 바뀜 #{r.changed_count}#{" — #{r.error}" if r.error}" }
      puts '예약된 캡처 없음' if runs.empty?
    end
  end
end
