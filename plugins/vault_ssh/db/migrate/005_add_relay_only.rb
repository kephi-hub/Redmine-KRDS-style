# 경유 전용 SSH 서버 — 다른 서버로 가는 길(경유)로만 쓰고 터미널 접속·명령 실행 대상에서 뺌 (VPN 점프 VM 등)
class AddRelayOnly < ActiveRecord::Migration[7.2]
  def change
    add_column :vault_ssh_profiles, :relay_only, :boolean, default: false, null: false
  end
end
