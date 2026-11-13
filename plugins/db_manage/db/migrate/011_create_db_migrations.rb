# DB 이관 (개발 ↔ 운영) — 실행 기록, DB 서버의 이관용(쓰기) 계정
class CreateDbMigrations < ActiveRecord::Migration[7.2]
  def change
    create_table :db_migrations do |t|
      t.references :project, null: false, index: true
      t.integer :source_link_id
      t.integer :target_link_id
      t.string :source_name, limit: 60
      t.string :target_name, limit: 60
      t.boolean :target_production, null: false, default: false
      t.integer :user_id
      t.string :status, limit: 10, null: false, default: 'queued'
      t.text :plan
      t.text :results
      t.string :reason, limit: 255
      t.text :error
      t.boolean :backup_removed, null: false, default: false
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_column :db_servers, :write_username, :string, limit: 120
    add_column :db_servers, :write_password_encrypted, :text
  end
end
