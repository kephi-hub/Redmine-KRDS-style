# 메뉴 구조도의 메뉴 한 줄 — parent_id 로 트리(뎁스 제한 없음), position 은 같은 부모 안 순서
class MenuItem < ApplicationRecord
  SCREEN_TYPES = %w(list detail form popup tab link).freeze
  CHANNELS = %w(both pc mobile).freeze
  # 메뉴에는 보이지 않고 화면만 있는 유형 (메뉴 노출 기본값 N)
  SCREEN_ONLY = %w(detail form popup tab).freeze

  belongs_to :project
  belongs_to :parent, class_name: 'MenuItem', optional: true
  belongs_to :menu_site, optional: true
  has_many :children, -> { order(:position, :id) }, class_name: 'MenuItem', foreign_key: :parent_id, dependent: :destroy
  has_many :menu_item_issues, dependent: :delete_all
  has_many :issues, through: :menu_item_issues
  has_many :menu_role_accesses, dependent: :delete_all

  serialize :extra, coder: JSON

  validates :name, presence: true, length: { maximum: 150 }
  validates :screen_id, length: { maximum: 60 }
  validates :url, length: { maximum: 500 }
  validates :screen_type, inclusion: { in: SCREEN_TYPES }, allow_blank: true
  validates :channel, inclusion: { in: CHANNELS }, allow_blank: true
  validate :parent_in_same_project
  validate :site_in_same_project

  before_validation { self.name = name.to_s.strip; self.screen_id = screen_id.to_s.strip.presence; self.url = url.to_s.strip.presence }
  # 화면 유형을 바꾸면 메뉴 노출 기본값도 따라감 (같이 바꾸거나 keep_in_menu 로 직접 정한 경우는 그 값)
  attr_accessor :keep_in_menu
  before_validation { self.in_menu = !SCREEN_ONLY.include?(screen_type) if will_save_change_to_screen_type? && !will_save_change_to_in_menu? && !keep_in_menu }
  # 하위 메뉴는 1뎁스 메뉴와 같은 사이트
  before_validation { self.menu_site_id = parent.menu_site_id if parent }
  after_save :spread_site, if: :saved_change_to_menu_site_id?

  def extra
    super || {}
  end

  def parent_in_same_project
    return unless parent
    errors.add(:parent_id, :invalid) if parent.project_id != project_id || parent.id == id
  end

  def site_in_same_project
    errors.add(:menu_site_id, :invalid) if menu_site && menu_site.project_id != project_id
  end

  # 사이트가 바뀌면 하위 메뉴도 같이
  def spread_site
    ids = descendant_ids(MenuItem.where(project_id: project_id).to_a.group_by(&:parent_id))
    MenuItem.where(id: ids).update_all(menu_site_id: menu_site_id) if ids.any?
  end

  # 프로젝트 메뉴를 트리 순서(앞순서 순회)로 [메뉴, 뎁스] 목록 — 한 번의 조회로
  # site: 사이트 id(그 사이트만), nil 이면 전체(사이트 순서 → 메뉴 순서)
  def self.ordered(project, site: nil)
    all = where(project_id: project.id).order(:position, :id).to_a
    by_parent = all.group_by(&:parent_id)
    site_order = MenuSite.names_for(project.id).keys.each_with_index.to_h
    roots = (by_parent[nil] || []).sort_by { |m| [site_order[m.menu_site_id] || -1, m.position, m.id] }
    roots = roots.select { |m| m.menu_site_id == site.to_i } if site
    out = []
    walk = lambda do |pid, depth|
      (by_parent[pid] || []).each { |m| out << [m, depth]; walk.call(m.id, depth + 1) }
    end
    roots.each { |m| out << [m, 0]; walk.call(m.id, 1) }
    out
  end

  # 사이트 이름 (사이트가 둘 이상인 프로젝트에서만 — 하나뿐이면 굳이 표시하지 않음)
  def site_label
    names = MenuSite.names_for(project_id)
    names.size > 1 ? names[menu_site_id] : nil
  end

  # 화면인지 — 화면 유형·화면 ID 가 있거나 하위가 없는 말단 (목록 아래에 상세·등록을 둬도 목록은 화면)
  def screen?(has_children)
    !has_children || screen_type.present? || screen_id.present?
  end

  # ordered([메뉴, 뎁스]) 중 화면만
  def self.screens(ordered)
    parents = ordered.map { |m, _| m.parent_id }.compact.to_set
    ordered.map(&:first).select { |m| m.screen?(parents.include?(m.id)) }
  end

  # 메뉴 고르기 목록의 이름 — 사이트가 둘 이상이면 1뎁스 앞에 [사이트]
  def pick_label(depth)
    depth.to_i.zero? && (label = site_label) ? "[#{label}] #{name}" : name
  end

  # "고객관리 > 고객목록" 형식의 경로 (index: id → 메뉴), 사이트가 둘 이상이면 "[관리자 페이지] 고객관리 > 고객목록"
  def path(index = nil, site: true)
    names = []
    node = self
    seen = {}
    while node && !seen[node.id]
      seen[node.id] = true
      names.unshift(node.name)
      node = index ? index[node.parent_id] : node.parent
    end
    text = names.join(' > ')
    (label = site && site_label) ? "[#{label}] #{text}" : text
  end

  def descendant_ids(by_parent)
    (by_parent[id] || []).flat_map { |c| [c.id] + c.descendant_ids(by_parent) }
  end

  def to_s
    name
  end
end
