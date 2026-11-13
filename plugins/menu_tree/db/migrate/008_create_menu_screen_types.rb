# 화면 유형 (프로젝트별) — 없으면 기본 6가지(목록·상세·등록·수정·팝업·탭·링크)를 씀. 처음 저장할 때 기본값까지 함께 저장됨
class CreateMenuScreenTypes < ActiveRecord::Migration[7.2]
  def change
    create_table :menu_screen_types do |t|
      t.references :project, null: false, index: true
      t.string :code, limit: 20, null: false
      t.string :name, limit: 30, null: false
      t.boolean :in_menu, null: false, default: true
      t.integer :position, null: false, default: 1
      t.timestamps
    end
    add_index :menu_screen_types, [:project_id, :code], unique: true
  end
end
