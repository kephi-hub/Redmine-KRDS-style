# 프로젝트 DB 연결의 '운영' 체크 제거 — DB 서버의 개발/운영 구분을 따름
class RemoveProductionFromDbLinks < ActiveRecord::Migration[7.2]
  def change
    remove_column :db_links, :production, :boolean, null: false, default: false
  end
end
