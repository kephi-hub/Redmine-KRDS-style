# 화면에 보이는 메뉴·모듈 이름 바꾸기 (관리 → 메뉴·모듈 이름) — kind: top(상단 메뉴) · group(프로젝트 대분류) · project(프로젝트 메뉴) · module(모듈)
class CreateKrdsLabels < ActiveRecord::Migration[7.2]
  def change
    create_table :krds_labels do |t|
      t.string :kind, limit: 10, null: false
      t.string :key, limit: 60, null: false
      t.string :name, limit: 60, null: false
      t.timestamps
    end
    add_index :krds_labels, [:kind, :key], unique: true
  end
end
