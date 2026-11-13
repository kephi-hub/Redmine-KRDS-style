# 감리 지적사항 · 투입 인력 · 보안 취약점 진단
class CreateAuditsStaffSec < ActiveRecord::Migration[7.2]
  def change
    create_table :pm_audit_rounds do |t|
      t.references :project, null: false, index: true
      t.string :name, limit: 100, null: false
      t.string :phase, limit: 20, null: false, default: 'analysis'
      t.date :start_on
      t.date :end_on
      t.string :auditor, limit: 100
      t.text :note
      t.timestamps
    end
    create_table :pm_audits do |t|
      t.references :project, null: false, index: true
      t.integer :pm_audit_round_id, index: true
      t.string :code, limit: 30, null: false
      t.string :area, limit: 20, null: false, default: 'pm'
      t.string :kind, limit: 20, null: false, default: 'advise'
      t.string :title, limit: 200, null: false
      t.text :content
      t.string :basis, limit: 200
      t.text :plan
      t.integer :owner_id
      t.date :due_on
      t.text :result
      t.string :status, limit: 20, null: false, default: 'received'
      t.date :done_on
      t.date :verified_on
      t.integer :issue_id
      t.integer :pm_deliverable_id
      t.integer :author_id
      t.timestamps
    end
    add_index :pm_audits, [:project_id, :code], unique: true
    create_table :pm_staffs do |t|
      t.references :project, null: false, index: true
      t.integer :user_id
      t.string :name, limit: 60, null: false
      t.string :company, limit: 100
      t.string :role, limit: 20, null: false, default: 'dev'
      t.string :grade, limit: 20
      t.date :start_on
      t.date :end_on
      t.integer :rate, null: false, default: 100
      t.date :pledge_on
      t.text :accounts
      t.date :revoked_on
      t.integer :replace_of_id
      t.string :replace_reason, limit: 200
      t.date :replace_approved_on
      t.text :note
      t.timestamps
    end
    create_table :pm_sec_scans do |t|
      t.references :project, null: false, index: true
      t.string :name, limit: 100, null: false
      t.string :tool, limit: 60
      t.date :scanned_on
      t.string :revision, limit: 40
      t.string :scanner, limit: 60
      t.text :note
      t.timestamps
    end
    create_table :pm_sec_items do |t|
      t.references :project, null: false, index: true
      t.integer :pm_sec_scan_id, null: false, index: true
      t.string :item_key, limit: 40, null: false, index: true
      t.string :kind, limit: 150, null: false
      t.string :level, limit: 10, null: false, default: 'mid'
      t.string :file_path, limit: 500
      t.integer :line
      t.text :description
      t.string :status, limit: 10, null: false, default: 'open'
      t.text :reason
      t.integer :fixer_id
      t.date :fixed_on
      t.string :recheck, limit: 10
      t.integer :pm_program_id
      t.timestamps
    end
  end
end
