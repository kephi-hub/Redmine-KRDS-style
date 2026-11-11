# 산출물 · 변경요청 · 프로그램 목록 · 회의록 · 이슈·위험
class CreatePmDocs < ActiveRecord::Migration[7.2]
  def change
    create_table :pm_deliverables do |t|
      t.references :project, null: false, index: true
      t.string :phase, limit: 10, null: false
      t.string :code, limit: 30
      t.string :name, limit: 150, null: false
      t.boolean :required, null: false, default: true
      t.integer :owner_id
      t.string :status, limit: 10, null: false, default: 'none'
      t.string :version, limit: 20
      t.date :due_on
      t.date :submitted_on
      t.string :auto_kind, limit: 30
      t.text :note
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    create_table :pm_change_requests do |t|
      t.references :project, null: false, index: true
      t.string :code, limit: 30, null: false
      t.string :title, limit: 200, null: false
      t.text :description
      t.text :reason
      t.string :requester, limit: 120
      t.date :requested_on
      t.string :priority, limit: 10, null: false, default: 'normal'
      t.string :status, limit: 12, null: false, default: 'received'
      t.text :impact
      t.text :tables
      t.decimal :effort, precision: 7, scale: 1
      t.text :schedule_impact
      t.integer :decided_by_id
      t.date :decided_on
      t.text :decision_note
      t.integer :author_id
      t.timestamps
    end
    add_index :pm_change_requests, [:project_id, :code], unique: true
    create_table :pm_cr_links do |t|
      t.references :pm_change_request, null: false, index: true
      t.string :target_type, limit: 30, null: false
      t.integer :target_id, null: false
    end
    add_index :pm_cr_links, [:target_type, :target_id]
    create_table :pm_programs do |t|
      t.references :project, null: false, index: true
      t.string :code, limit: 60, null: false
      t.string :name, limit: 150, null: false
      t.string :kind, limit: 10, null: false, default: 'screen'
      t.integer :menu_item_id, index: true
      t.text :source_paths
      t.integer :developer_id
      t.string :status, limit: 10, null: false, default: 'todo'
      t.date :planned_on
      t.date :done_on
      t.text :note
      t.timestamps
    end
    add_index :pm_programs, [:project_id, :code], unique: true
    create_table :pm_meetings do |t|
      t.references :project, null: false, index: true
      t.string :title, limit: 200, null: false
      t.datetime :held_at, null: false
      t.string :place, limit: 120
      t.text :attendees
      t.text :agenda
      t.text :notes
      t.text :decisions
      t.text :actions
      t.integer :author_id
      t.timestamps
    end
    create_table :pm_risks do |t|
      t.references :project, null: false, index: true
      t.string :code, limit: 30, null: false
      t.string :kind, limit: 6, null: false, default: 'risk'
      t.string :title, limit: 200, null: false
      t.text :description
      t.integer :probability, null: false, default: 2
      t.integer :impact, null: false, default: 2
      t.string :status, limit: 12, null: false, default: 'open'
      t.integer :owner_id
      t.text :plan
      t.date :due_on
      t.integer :issue_id
      t.date :raised_on
      t.date :closed_on
      t.integer :author_id
      t.timestamps
    end
    add_index :pm_risks, [:project_id, :code], unique: true
  end
end
