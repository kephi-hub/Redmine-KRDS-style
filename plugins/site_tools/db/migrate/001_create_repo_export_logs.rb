# 소스코드 다운로드 기록 — 누가 어느 저장소의 어떤 경로·리비전을 받았는지
class CreateRepoExportLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :repo_export_logs do |t|
      t.integer :user_id
      t.integer :repository_id, index: true
      t.integer :project_id
      t.string :path, limit: 500
      t.string :rev, limit: 60
      t.bigint :bytes
      t.integer :files
      t.string :status, limit: 10, null: false
      t.string :message, limit: 255
      t.datetime :created_at, null: false
    end
  end
end
