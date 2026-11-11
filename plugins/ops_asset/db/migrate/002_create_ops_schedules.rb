# 시스템 스케줄러 — cron·Spring·Quartz·Windows·Jenkins·DB 잡 일정, 실행 서버(자산), 선후행·실패 대응
class CreateOpsSchedules < ActiveRecord::Migration[7.2]
  def change
    create_table :ops_schedules do |t|
      t.references :project, null: false, index: true
      t.string :name, limit: 150, null: false
      t.string :kind, limit: 12, null: false, default: 'cron'
      t.integer :ops_asset_id, index: true
      t.string :expression, limit: 255
      t.text :command
      t.string :run_as, limit: 60
      t.integer :duration_min
      t.text :depends_on
      t.text :on_failure
      t.string :owner, limit: 120
      t.text :related
      t.boolean :active, null: false, default: true
      t.string :source, limit: 12, null: false, default: 'manual'
      t.string :source_key, limit: 255
      t.text :note
      t.integer :author_id
      t.timestamps
    end
    add_index :ops_schedules, [:project_id, :source_key], name: 'idx_ops_sched_source'
  end
end
