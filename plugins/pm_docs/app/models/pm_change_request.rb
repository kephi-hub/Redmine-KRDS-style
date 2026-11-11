# 변경요청(CR) — 영향 분석(요구사항·메뉴·인터페이스·테이블·공수·일정), 승인·반려, 반영 일감
class PmChangeRequest < ApplicationRecord
  STATUSES = %w(received analyzing approved rejected done).freeze
  PRIORITIES = %w(high normal low).freeze
  LINK_TYPES = %w(requirement menu interface issue).freeze

  belongs_to :project
  belongs_to :decided_by, class_name: 'User', optional: true
  has_many :pm_cr_links, dependent: :delete_all

  validates :title, presence: true, length: { maximum: 200 }
  validates :status, inclusion: { in: STATUSES }
  validates :priority, inclusion: { in: PRIORITIES }
  validates :code, presence: true, length: { maximum: 30 }, uniqueness: { scope: :project_id, case_sensitive: false }
  validates :requester, length: { maximum: 120 }
  validates :effort, numericality: { greater_than_or_equal_to: 0, less_than: 100_000 }, allow_nil: true

  before_validation :fill_code

  scope :sorted, -> { order(code: :desc) }

  def self.next_code(project)
    nums = where(project_id: project.id).where('code LIKE ?', 'CR-%').pluck(:code).map { |c| c[/\ACR-(\d+)/, 1].to_i }
    format('CR-%03d', (nums.max || 0) + 1)
  end

  def fill_code
    self.code = code.to_s.strip.upcase.presence
    self.title = title.to_s.strip
    self.code ||= self.class.next_code(project) if project
  end

  def link_ids(type)
    pm_cr_links.select { |l| l.target_type == type }.map(&:target_id)
  end

  def set_links(type, ids)
    ids = ids.map(&:to_i).uniq
    old = link_ids(type)
    PmCrLink.where(pm_change_request_id: id, target_type: type, target_id: old - ids).delete_all
    (ids - old).each { |i| PmCrLink.create!(pm_change_request_id: id, target_type: type, target_id: i) }
    pm_cr_links.reset
  end

  def requirements
    defined?(QaRequirement) ? QaRequirement.where(id: link_ids('requirement'), project_id: project_id).to_a : []
  end

  def menus
    defined?(MenuItem) ? MenuItem.where(id: link_ids('menu'), project_id: project_id).to_a : []
  end

  def interfaces
    defined?(OpsInterface) ? OpsInterface.where(id: link_ids('interface'), project_id: project_id).to_a : []
  end

  def issues
    Issue.where(id: link_ids('issue')).includes(:status).to_a
  end

  def decided?
    %w(approved rejected done).include?(status)
  end
end
