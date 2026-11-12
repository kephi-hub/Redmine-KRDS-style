# 화면 캡처 로그인 확인 — 로그인 후 화면에 이 로그아웃 주소로 가는 링크·폼이 있으면 로그인 성공
class AddLogoutUrlToMenuCaptureConfigs < ActiveRecord::Migration[7.2]
  def change
    add_column :menu_capture_configs, :logout_url, :string, limit: 300
  end
end
