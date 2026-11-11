# 이슈·위험 관리대장 — 가능성·영향(1 하 · 2 중 · 3 상) → 등급(곱 6 이상 상, 3~4 중, 나머지 하)
class PmRisk < ApplicationRecord
  KINDS = %w(risk issue).freeze
  STATUSES = %w(open action watch closed occurred).freeze

  belongs_to :project
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :issue, optional: true

  validates :title, presence: true, length: { maximum: 200 }
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :probability, :impact, inclusion: { in: [1, 2, 3] }
  validates :code, presence: true, length: { maximum: 30 }, uniqueness: { scope: :project_id, case_sensitive: false }

  before_validation :fill_code

  scope :sorted, -> { order(code: :desc) }

  def self.next_code(project)
    nums = where(project_id: project.id).where('code LIKE ?', 'R-%').pluck(:code).map { |c| c[/\AR-(\d+)/, 1].to_i }
    format('R-%03d', (nums.max || 0) + 1)
  end

  def fill_code
    self.code = code.to_s.strip.upcase.presence
    self.title = title.to_s.strip
    self.code ||= self.class.next_code(project) if project
  end

  def score
    probability.to_i * impact.to_i
  end

  # high / mid / low
  def level
    score >= 6 ? 'high' : (score >= 3 ? 'mid' : 'low')
  end

  def open?
    %w(open action watch).include?(status)
  end
end
