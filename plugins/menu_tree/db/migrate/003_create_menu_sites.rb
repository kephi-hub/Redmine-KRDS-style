# 사이트(사용자 페이지·관리자 페이지 등) — 메뉴와 시스템 권한 등급을 사이트별로 나눔
class CreateMenuSites < ActiveRecord::Migration[7.2]
  def change
    create_table :menu_sites do |t|
      t.references :project, null: false, index: true
      t.string :name, limit: 60, null: false
      t.string :code, limit: 20
      t.string :url, limit: 300
      t.text :description
      t.integer :position, null: false, default: 1
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    # 메뉴는 모두 사이트 번호를 가짐(하위 메뉴는 1뎁스 메뉴와 같은 사이트), 비어 있으면 사이트 없음
    add_column :menu_items, :menu_site_id, :integer
    add_index :menu_items, :menu_site_id
    # 권한 등급의 적용 사이트 — 비어 있으면 모든 사이트
    add_column :sys_roles, :menu_site_id, :integer
  end
end
