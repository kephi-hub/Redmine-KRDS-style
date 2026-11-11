# 자산 만료 알림 메일 (Redmine 메일 양식·보내는 주소 사용)
class OpsAssetMailer < Mailer
  def expiry(user, assets, today)
    @assets = assets
    @today = today
    @user = user
    mail to: user, subject: "[#{Setting.app_title}] 만료 예정 자산 #{assets.size}건"
  end
end
