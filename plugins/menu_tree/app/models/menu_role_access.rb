# 메뉴 × 권한 등급의 접근 수준 — read(조회) · write(등록·수정) · full(삭제 포함). 행이 없으면 접근 없음
class MenuRoleAccess < ApplicationRecord
  LEVELS = %w(read write full).freeze
  CODES = { 'read' => 'R', 'write' => 'CRU', 'full' => 'CRUD' }.freeze

  belongs_to :menu_item
  belongs_to :sys_role
  validates :access, inclusion: { in: LEVELS }
end
