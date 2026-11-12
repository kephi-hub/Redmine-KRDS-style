# 감리 회차 (예: 요구정의 단계 감리) — 단계·기간·감리 기관
class PmAuditRound < ApplicationRecord
  PHASES = %w(analysis design close etc).freeze

  belongs_to :project
  has_many :pm_audits, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 100 }
  validates :phase, inclusion: { in: PHASES }
  validates :auditor, length: { maximum: 100 }

  scope :sorted, -> { order(Arel.sql('start_on IS NULL'), start_on: :desc, id: :desc) }

  def to_s
    name
  end
end
