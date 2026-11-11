# 메뉴 구조도 — 메뉴(트리, 뎁스 제한 없음), 프로젝트별 추가 칼럼, 메뉴 ↔ 일감 연결(여러 개)
class CreateMenuItems < ActiveRecord::Migration[7.2]
  def change
    create_table :menu_items do |t|
      t.references :project, null: false, index: true
      t.integer :parent_id, index: true
      t.integer :position, null: false, default: 1
      t.string :name, limit: 150, null: false
      t.string :screen_id, limit: 60
      t.string :url, limit: 500
      t.string :screen_type, limit: 20
      t.string :channel, limit: 20
      t.boolean :active, null: false, default: true
      t.text :note
      t.text :extra
      t.integer :author_id
      t.timestamps
    end
    add_index :menu_items, [:project_id, :parent_id, :position]

    create_table :menu_columns do |t|
      t.references :project, null: false, index: true
      t.string :name, limit: 60, null: false
      t.string :kind, limit: 10, null: false, default: 'text'
      t.text :options
      t.integer :position, null: false, default: 1
      t.timestamps
    end

    create_table :menu_item_issues do |t|
      t.references :menu_item, null: false
      t.references :issue, null: false, index: true
    end
    add_index :menu_item_issues, [:menu_item_id, :issue_id], unique: true
  end
end
