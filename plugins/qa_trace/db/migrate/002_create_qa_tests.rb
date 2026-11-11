# 테스트 — 케이스(메뉴·요구사항 연결), 회차, 회차 × 케이스 결과(결함 일감 연결)
class CreateQaTests < ActiveRecord::Migration[7.2]
  def change
    create_table :qa_test_cases do |t|
      t.references :project, null: false, index: true
      t.string :code, limit: 30, null: false
      t.string :kind, limit: 12, null: false, default: 'unit'
      t.integer :menu_item_id, index: true
      t.string :name, limit: 200, null: false
      t.text :precondition
      t.text :steps
      t.text :expected
      t.boolean :active, null: false, default: true
      t.integer :author_id
      t.timestamps
    end
    add_index :qa_test_cases, [:project_id, :code], unique: true

    create_table :qa_case_requirements do |t|
      t.references :qa_test_case, null: false
      t.references :qa_requirement, null: false, index: true
    end
    add_index :qa_case_requirements, [:qa_test_case_id, :qa_requirement_id], unique: true, name: 'idx_qa_case_reqs'

    create_table :qa_test_runs do |t|
      t.references :project, null: false, index: true
      t.string :name, limit: 100, null: false
      t.string :kind, limit: 12
      t.date :start_on
      t.date :end_on
      t.string :status, limit: 10, null: false, default: 'open'
      t.text :note
      t.integer :author_id
      t.timestamps
    end

    create_table :qa_test_results do |t|
      t.references :qa_test_run, null: false
      t.references :qa_test_case, null: false, index: true
      t.string :result, limit: 10, null: false, default: 'none'
      t.integer :user_id
      t.datetime :tested_at
      t.text :note
      t.integer :issue_id, index: true
    end
    add_index :qa_test_results, [:qa_test_run_id, :qa_test_case_id], unique: true, name: 'idx_qa_run_cases'
  end
end
