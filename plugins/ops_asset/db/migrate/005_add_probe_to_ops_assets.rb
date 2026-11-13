# 자산 자동 확인 — 서버: SSH 접속정보(접속정보 vault_ssh)로 OS·CPU·메모리·디스크 수집, 인증서·도메인: HTTPS 인증서 만료일 확인
class AddProbeToOpsAssets < ActiveRecord::Migration[7.2]
  def change
    add_column :ops_assets, :vault_key_id, :integer
    add_column :ops_assets, :server_info, :text
    add_column :ops_assets, :disk_pct, :integer
    add_column :ops_assets, :info_at, :datetime
    add_column :ops_assets, :info_error, :string, limit: 255
    add_column :ops_assets, :cert_info, :text
    add_column :ops_assets, :cert_at, :datetime
    add_column :ops_assets, :cert_error, :string, limit: 255
  end
end
