# 메뉴 노출 — Y: 사이트 메뉴에 보이는 항목, N: 메뉴에는 없고 화면만 있는 것(상세·등록·수정·팝업·탭 등)
class AddInMenuToMenuItems < ActiveRecord::Migration[7.2]
  def change
    add_column :menu_items, :in_menu, :boolean, null: false, default: true
    up_only { execute "UPDATE menu_items SET in_menu = #{connection.quoted_false} WHERE screen_type IN ('detail', 'form', 'popup', 'tab')" }
  end
end
