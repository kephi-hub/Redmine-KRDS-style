# 시스템 권한 — 개발 대상 시스템의 사용자 권한 등급과 메뉴별 접근 수준(조회/편집/전체)
class CreateSysRoles < ActiveRecord::Migration[7.2]
  def change
    create_table :sys_roles do |t|
      t.references :project, null: false, index: true
      t.string :name, limit: 60, null: false
      t.string :code, limit: 30
      t.integer :level, null: false, default: 1
      t.text :description
      t.integer :position, null: false, default: 1
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    create_table :menu_role_accesses do |t|
      t.references :menu_item, null: false
      t.references :sys_role, null: false, index: true
      t.string :access, limit: 10, null: false
    end
    add_index :menu_role_accesses, [:menu_item_id, :sys_role_id], unique: true
  end
end
