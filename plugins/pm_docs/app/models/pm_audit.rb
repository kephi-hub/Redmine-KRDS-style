# 감리 지적사항 — AU-001 자동, 회차·영역·구분, 조치 계획 → 조치 결과 → 확인
class PmAudit < ApplicationRecord
  AREAS = %w(pm app db arch sec test etc).freeze
  KINDS = %w(correct advise note).freeze
  STATUSES = %w(received planned acting done verified).freeze

  belongs_to :project
  belongs_to :pm_audit_round, optional: true
  belongs_to :owner, class_name: 'User', optional: true
  belongs_to :issue, optional: true
  belongs_to :pm_deliverable, optional: true

  validates :title, presence: true, length: { maximum: 200 }
  validates :code, presence: true, length: { maximum: 30 }, uniqueness: { scope: :project_id, case_sensitive: false }
  validates :area, inclusion: { in: AREAS }
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :basis, length: { maximum: 200 }
  validate { errors.add(:pm_audit_round_id, :invalid) if pm_audit_round && pm_audit_round.project_id != project_id }

  before_validation :fill_code
  before_save do
    self.done_on ||= User.current.today if %w(done verified).include?(status)
    self.verified_on ||= User.current.today if status == 'verified'
  end

  scope :sorted, -> { order(:code) }

  def self.next_code(project)
    nums = where(project_id: project.id).where('code LIKE ?', 'AU-%').pluck(:code).map { |c| c[/\AAU-(\d+)/, 1].to_i }
    format('AU-%03d', (nums.max || 0) + 1)
  end

  def fill_code
    self.code = code.to_s.strip.upcase.presence
    self.title = title.to_s.strip
    self.code ||= self.class.next_code(project) if project
  end

  # 조치가 끝나지 않음 (확인 완료 전까지 열림)
  def open?
    status != 'verified'
  end

  def late?(today = User.current.today)
    due_on && due_on < today && !%w(done verified).include?(status)
  end
end
