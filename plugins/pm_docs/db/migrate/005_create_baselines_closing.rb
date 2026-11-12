# 일정 기준선(시점별 일감 일정 저장) · 준공 체크리스트(수동 항목 확인 기록)
class CreateBaselinesClosing < ActiveRecord::Migration[7.2]
  def change
    create_table :pm_baselines do |t|
      t.references :project, null: false, index: true
      t.string :name, limit: 100, null: false
      t.date :taken_on, null: false
      t.date :start_on
      t.date :end_on
      t.integer :issue_count, null: false, default: 0
      t.text :note
      t.integer :author_id
      t.timestamps
    end
    create_table :pm_baseline_items do |t|
      t.references :pm_baseline, null: false, index: true
      t.integer :issue_id, null: false, index: true
      t.string :subject, limit: 255
      t.date :start_date
      t.date :due_date
      t.integer :done_ratio
      t.float :estimated_hours
    end
    create_table :pm_closing_checks do |t|
      t.references :project, null: false, index: true
      t.string :key, limit: 40, null: false
      t.boolean :done, null: false, default: false
      t.text :note
      t.integer :user_id
      t.datetime :checked_at
    end
    add_index :pm_closing_checks, [:project_id, :key], unique: true
  end
end
