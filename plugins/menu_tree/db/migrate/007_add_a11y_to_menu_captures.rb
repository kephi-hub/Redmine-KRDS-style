# 웹 접근성 자동 점검 — 캡처할 때 axe-core 로 검사한 위반(JSON)과 건수, 설정의 점검 여부
class AddA11yToMenuCaptures < ActiveRecord::Migration[7.2]
  def change
    add_column :menu_captures, :a11y, :text
    add_column :menu_captures, :a11y_count, :integer
    add_column :menu_capture_configs, :a11y, :boolean, null: false, default: true
  end
end
