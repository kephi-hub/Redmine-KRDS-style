# DB 서버 SSH 터널 (예: Redmine → WEB 서버 → 운영 DB). 비밀번호·개인키는 암호화해 저장, 지문은 첫 연결 때 기록
class AddSshTunnelToDbServers < ActiveRecord::Migration[7.2]
  def change
    add_column :db_servers, :ssh_enabled, :boolean, null: false, default: false
    add_column :db_servers, :ssh_host, :string, limit: 255
    add_column :db_servers, :ssh_port, :integer, null: false, default: 22
    add_column :db_servers, :ssh_username, :string, limit: 120
    add_column :db_servers, :ssh_auth, :string, limit: 10, null: false, default: 'password'
    add_column :db_servers, :ssh_password_encrypted, :text
    add_column :db_servers, :ssh_key_encrypted, :text
    add_column :db_servers, :ssh_passphrase_encrypted, :text
    add_column :db_servers, :ssh_host_key, :string, limit: 120
  end
end
