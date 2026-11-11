# DB 서버 개발/운영 구분 (배포 환경의 운영 표시와 같은 방식)
class AddProductionToDbServers < ActiveRecord::Migration[7.2]
  def change
    add_column :db_servers, :production, :boolean, null: false, default: false
  end
end
