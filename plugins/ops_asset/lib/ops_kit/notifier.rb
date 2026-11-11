# 자산 만료 알림 메일 — 만료 30·7·1일 전, 당일, 만료 다음 날에 한 번씩 (매일 cron 으로 rake redmine:ops_asset:notify)
# 받는 사람: 프로젝트 자산은 그 프로젝트에서 "자산 편집" 권한이 있는 구성원, 공용 자산은 관리자 + 연결된 프로젝트의 그 구성원
# 메일 발송이 꺼져 있으면(관리 > 메일 서버) 보내지 않고 대상만 알려 줌
module OpsKit
  module Notifier
    module_function

    def due(today = Date.current)
      days = OpsAsset::ALERT_DAYS + [-1]
      OpsAsset.where(active: true).where.not(expires_on: nil).to_a.select { |a| days.include?(a.days_left(today)) }
    end

    def recipients(asset)
      projects = asset.shared? ? asset.linked_projects.to_a : [asset.project].compact
      users = projects.flat_map do |p|
        next [] unless p.active? && p.module_enabled?(:ops_assets)
        p.users.select { |u| u.active? && u.allowed_to?(:manage_ops_assets, p) }
      end
      users += User.active.where(admin: true).to_a if asset.shared?
      users.uniq.select { |u| u.mail.present? }
    end

    # { user => [asset, …] } 로 묶어 한 사람에게 한 통
    def run(today = Date.current, dry_run: false)
      by_user = Hash.new { |h, k| h[k] = [] }
      due(today).each { |a| recipients(a).each { |u| by_user[u] << a } }
      sent = 0
      unless dry_run || !ActionMailer::Base.perform_deliveries
        by_user.each do |user, assets|
          OpsAssetMailer.expiry(user, assets.sort_by(&:expires_on), today).deliver_now
          sent += 1
        end
      end
      { due: by_user.values.flatten.uniq.size, users: by_user.size, sent: sent, deliveries: ActionMailer::Base.perform_deliveries }
    end
  end
end
