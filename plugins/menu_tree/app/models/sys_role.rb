# 개발 대상 시스템의 사용자 권한 등급 (예: 일반회원·기업회원·운영자·관리자). level 이 클수록 높은 등급
class SysRole < ApplicationRecord
  belongs_to :project
  has_many :menu_role_accesses, dependent: :delete_all

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :project_id, case_sensitive: false }
  validates :code, length: { maximum: 30 }, format: { with: /\A[A-Za-z0-9_\-]*\z/ }
  validates :level, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 999 }

  scope :sorted, -> { order(level: :desc, position: :asc, id: :asc) }
  scope :active, -> { where(active: true) }

  before_validation { self.code = code.to_s.strip.upcase.presence }

  def to_s
    name
  end
end
