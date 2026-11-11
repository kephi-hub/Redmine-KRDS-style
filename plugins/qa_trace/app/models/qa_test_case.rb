# 테스트 케이스 — 메뉴(화면) 하나, 요구사항 여러 개, ID 비워 두면 TC-001 처럼 자동
class QaTestCase < ApplicationRecord
  KINDS = %w(unit integration acceptance).freeze

  belongs_to :project
  belongs_to :menu_item, optional: true
  has_many :qa_case_requirements, dependent: :delete_all
  has_many :qa_requirements, through: :qa_case_requirements
  has_many :qa_test_results, dependent: :delete_all

  validates :name, presence: true, length: { maximum: 200 }
  validates :kind, inclusion: { in: KINDS }
  validates :code, presence: true, length: { maximum: 30 }, format: { with: /\A[A-Za-z0-9][A-Za-z0-9_.\-]*\z/ },
                   uniqueness: { scope: :project_id, case_sensitive: false }
  validate :menu_in_project

  before_validation :fill_code

  scope :sorted, -> { order(:code) }
  scope :active, -> { where(active: true) }

  def self.next_code(project)
    nums = where(project_id: project.id).where('code LIKE ?', 'TC-%').pluck(:code).map { |c| c[/\ATC-(\d+)/, 1].to_i }
    format('TC-%03d', (nums.max || 0) + 1)
  end

  def fill_code
    self.code = code.to_s.strip.upcase.presence
    self.name = name.to_s.strip
    self.code ||= self.class.next_code(project) if project
  end

  def menu_in_project
    errors.add(:menu_item_id, :invalid) if menu_item && menu_item.project_id != project_id
  end

  def to_s
    "#{code} #{name}"
  end
end
