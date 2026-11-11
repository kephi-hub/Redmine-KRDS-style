# 메뉴 구조도의 메뉴 한 줄 — parent_id 로 트리(뎁스 제한 없음), position 은 같은 부모 안 순서
class MenuItem < ApplicationRecord
  SCREEN_TYPES = %w(list detail form popup tab link).freeze
  CHANNELS = %w(both pc mobile).freeze

  belongs_to :project
  belongs_to :parent, class_name: 'MenuItem', optional: true
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

  before_validation { self.name = name.to_s.strip; self.screen_id = screen_id.to_s.strip.presence; self.url = url.to_s.strip.presence }

  def extra
    super || {}
  end

  def parent_in_same_project
    return unless parent
    errors.add(:parent_id, :invalid) if parent.project_id != project_id || parent.id == id
  end

  # 프로젝트 메뉴 전체를 트리 순서(앞순서 순회)로 [메뉴, 뎁스] 목록 — 한 번의 조회로
  def self.ordered(project)
    all = where(project_id: project.id).order(:position, :id).to_a
    by_parent = all.group_by(&:parent_id)
    out = []
    walk = lambda do |pid, depth|
      (by_parent[pid] || []).each { |m| out << [m, depth]; walk.call(m.id, depth + 1) }
    end
    walk.call(nil, 0)
    out
  end

  # "고객관리 > 고객목록" 형식의 경로 (index: id → 메뉴)
  def path(index = nil)
    names = []
    node = self
    seen = {}
    while node && !seen[node.id]
      seen[node.id] = true
      names.unshift(node.name)
      node = index ? index[node.parent_id] : node.parent
    end
    names.join(' > ')
  end

  def descendant_ids(by_parent)
    (by_parent[id] || []).flat_map { |c| [c.id] + c.descendant_ids(by_parent) }
  end

  def to_s
    name
  end
end
