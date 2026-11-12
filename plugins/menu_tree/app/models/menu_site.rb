# 메뉴 구조도의 사이트 (예: 사용자 페이지 · 관리자 페이지) — 한 프로젝트에 여러 개
class MenuSite < ApplicationRecord
  belongs_to :project
  has_many :menu_items, dependent: :restrict_with_error
  has_many :sys_roles, dependent: :nullify

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :project_id, case_sensitive: false }
  validates :code, length: { maximum: 20 }, format: { with: /\A[A-Za-z0-9_\-]*\z/ }
  validates :url, length: { maximum: 300 }

  scope :sorted, -> { order(:position, :id) }

  before_validation { self.name = name.to_s.strip; self.code = code.to_s.strip.upcase.presence; self.url = url.to_s.strip.presence }
  # 처음 만든 사이트는 사이트가 없던 기존 메뉴를 모두 가져감
  after_create { MenuItem.where(project_id: project_id, menu_site_id: nil).update_all(menu_site_id: id) if MenuSite.where(project_id: project_id).count == 1 }

  after_save { MenuTree::Current.sites&.delete(project_id) }
  after_destroy { MenuTree::Current.sites&.delete(project_id) }

  def to_s
    name
  end

  # 요청 하나 안에서 프로젝트별 사이트 이름을 한 번만 읽음 { id => 이름 }
  def self.names_for(project_id)
    cache = (MenuTree::Current.sites ||= {})
    cache[project_id] ||= where(project_id: project_id).sorted.pluck(:id, :name).to_h
  end
end
