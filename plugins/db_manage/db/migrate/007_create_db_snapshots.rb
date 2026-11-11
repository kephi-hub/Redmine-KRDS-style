# DB 구조 변경 이력 — 연결(개발DB·운영DB 등)마다 구조(테이블·컬럼·인덱스·객체 정의)를 압축해 저장, 바뀌었을 때만
class CreateDbSnapshots < ActiveRecord::Migration[7.2]
  def change
    create_table :db_snapshots do |t|
      t.references :db_link, null: false, index: true
      t.integer :user_id
      t.string :digest, limit: 64, null: false
      t.integer :table_count, null: false, default: 0
      t.integer :column_count, null: false, default: 0
      t.integer :object_count, null: false, default: 0
      t.text :summary
      t.binary :data, limit: 64.megabytes
      t.datetime :created_at, null: false
    end
  end
end
