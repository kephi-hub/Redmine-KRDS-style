# SQL 조회 실행 기록 (거부된 것 포함)
class CreateDbQueryLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :db_query_logs do |t|
      t.references :db_link, null: false, index: true
      t.integer :user_id, index: true
      t.text :sql
      t.string :status, limit: 10, null: false
      t.integer :row_count
      t.integer :duration_ms
      t.string :message, limit: 255
      t.datetime :created_at, null: false
    end
  end
end
