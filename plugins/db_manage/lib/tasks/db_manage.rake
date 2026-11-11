# DB 구조 자동 저장 (변경 이력) — cron 에서 하루 한 번 등 (setup/cron.example)
#   docker compose exec -T -u redmine redmine bundle exec rake redmine:db_manage:snapshot
namespace :redmine do
  namespace :db_manage do
    desc 'DB 관리 모듈이 켜진 프로젝트의 DB 구조를 저장 (바뀐 경우만)'
    task snapshot: :environment do
      DbLink.includes(:project, :db_server).find_each do |link|
        next unless link.project.active? && link.project.module_enabled?(:db_manage)
        begin
          state, rec = DbSnapshot.capture(link)
          puts "#{link.project.identifier}/#{link.name}: #{state == :saved ? "저장 (테이블 #{rec.table_count})" : '바뀐 것 없음'}"
        rescue DbManage::Error, StandardError => e
          puts "#{link.project.identifier}/#{link.name}: 실패 — #{e.message.to_s.truncate(200)}"
        end
      end
    end
  end
end
