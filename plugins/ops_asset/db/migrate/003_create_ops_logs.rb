# 점검·장애 — 점검표 양식, 정기점검(항목별 결과는 JSON), 장애 기록
class CreateOpsLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :ops_check_templates do |t|
      t.references :project, null: false, index: true
      t.string :name, limit: 100, null: false
      t.text :items
      t.timestamps
    end
    create_table :ops_checks do |t|
      t.references :project, null: false, index: true
      t.integer :ops_check_template_id
      t.string :name, limit: 120, null: false
      t.date :checked_on, null: false
      t.integer :user_id
      t.text :results
      t.text :note
      t.timestamps
    end
    create_table :ops_incidents do |t|
      t.references :project, null: false, index: true
      t.string :title, limit: 200, null: false
      t.string :grade, limit: 4, null: false, default: '3'
      t.string :status, limit: 10, null: false, default: 'open'
      t.datetime :occurred_at, null: false
      t.datetime :detected_at
      t.datetime :recovered_at
      t.integer :ops_asset_id
      t.string :target, limit: 200
      t.text :impact
      t.text :cause
      t.text :action
      t.text :prevention
      t.integer :issue_id, index: true
      t.integer :author_id
      t.timestamps
    end
  end
end
