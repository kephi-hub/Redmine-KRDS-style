# 장애 기록 — 발생·인지·복구 시각으로 중단 시간 계산, 일감 연결(선택)
class OpsIncident < ApplicationRecord
  GRADES = %w(1 2 3 4).freeze
  STATUSES = %w(open closed).freeze

  belongs_to :project
  belongs_to :ops_asset, optional: true
  belongs_to :issue, optional: true

  validates :title, presence: true, length: { maximum: 200 }
  validates :grade, inclusion: { in: GRADES }
  validates :status, inclusion: { in: STATUSES }
  validates :occurred_at, presence: true
  validates :target, length: { maximum: 200 }
  validate :times_in_order

  scope :sorted, -> { order(occurred_at: :desc, id: :desc) }

  def times_in_order
    errors.add(:detected_at, :greater_than_start_date) if detected_at && occurred_at && detected_at < occurred_at
    errors.add(:recovered_at, :greater_than_start_date) if recovered_at && occurred_at && recovered_at < occurred_at
  end

  # 중단 시간(분): 복구 - 발생 (복구 전이면 nil)
  def downtime_min
    recovered_at && occurred_at ? ((recovered_at - occurred_at) / 60).round : nil
  end

  def detect_min
    detected_at && occurred_at ? ((detected_at - occurred_at) / 60).round : nil
  end
end
