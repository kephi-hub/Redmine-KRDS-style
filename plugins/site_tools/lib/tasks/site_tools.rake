namespace :redmine do
  namespace :site_tools do
    desc '모든 저장소의 미연결 커미터를 사용자 로그인 ID·메일 기준으로 연결'
    task map_committers: :environment do
      idx = SiteTools::Committers.user_index
      Repository.find_each do |repo|
        r = SiteTools::Committers.refresh(repo, idx)
        puts "#{repo.project&.identifier}/#{repo.identifier.presence || '(기본)'}: 연결 #{r[:mapped].size}, 이미 #{r[:already]}, 미연결 #{r[:unmatched].size}"
      end
    end
  end
end
