# 요구사항 — 공공 표준 분류(SFR·PER…) ID, 메뉴·일감 연결(여러 개), 변경 이력
class CreateQaRequirements < ActiveRecord::Migration[7.2]
  def change
    create_table :qa_requirements do |t|
      t.references :project, null: false, index: true
      t.string :code, limit: 30, null: false
      t.string :category, limit: 5, null: false
      t.string :name, limit: 200, null: false
      t.text :description
      t.string :source, limit: 200
      t.string :priority, limit: 10, null: false, default: 'normal'
      t.string :status, limit: 10, null: false, default: 'received'
      t.integer :parent_id, index: true
      t.integer :author_id
      t.timestamps
    end
    add_index :qa_requirements, [:project_id, :code], unique: true

    create_table :qa_requirement_menus do |t|
      t.references :qa_requirement, null: false
      t.references :menu_item, null: false, index: true
    end
    add_index :qa_requirement_menus, [:qa_requirement_id, :menu_item_id], unique: true, name: 'idx_qa_req_menus'

    create_table :qa_requirement_issues do |t|
      t.references :qa_requirement, null: false
      t.references :issue, null: false, index: true
    end
    add_index :qa_requirement_issues, [:qa_requirement_id, :issue_id], unique: true, name: 'idx_qa_req_issues'

    create_table :qa_requirement_logs do |t|
      t.references :qa_requirement, null: false, index: true
      t.integer :user_id
      t.text :details
      t.datetime :created_at, null: false
    end
  end
end
