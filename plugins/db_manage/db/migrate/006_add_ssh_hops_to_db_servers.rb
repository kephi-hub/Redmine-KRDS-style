# SSH 다단계 경유 (예: WEB → WAS → DB) — 첫 서버 다음의 경유 서버들(계정·비밀값·지문)을 암호화한 JSON 으로
class AddSshHopsToDbServers < ActiveRecord::Migration[7.2]
  def change
    add_column :db_servers, :ssh_hops_encrypted, :text
  end
end
