# 투입 인력 — 역할·등급·투입 기간·투입률, 계획 M/M(기간 × 투입률) · 실적 M/M(소요시간 ÷ 168시간),
# 보안서약서·계정 발급·회수, 교체 이력(교체 전 인력·사유·승인일)
class PmStaff < ApplicationRecord
  ROLES = %w(pm pl dev design pub dba qa etc).freeze
  GRADES = %w(special high mid low).freeze
  HOURS_PER_MM = 168.0

  belongs_to :project
  belongs_to :user, optional: true
  belongs_to :replace_of, class_name: 'PmStaff', optional: true

  validates :name, presence: true, length: { maximum: 60 }
  validates :company, length: { maximum: 100 }
  validates :role, inclusion: { in: ROLES }
  validates :grade, inclusion: { in: GRADES }, allow_blank: true
  validates :rate, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100 }
  validates :replace_reason, length: { maximum: 200 }
  validate { errors.add(:end_on, :greater_than_start_date) if start_on && end_on && end_on < start_on }

  before_validation { self.name = user.name if name.blank? && user }

  scope :sorted, -> { order(Arel.sql('end_on IS NOT NULL'), :start_on, :id) }

  def active?(date = User.current.today)
    (start_on.nil? || start_on <= date) && (end_on.nil? || end_on >= date)
  end

  # from~to 사이 계획 M/M — 달마다 (겹친 날 ÷ 그 달 날 수) × 투입률
  def plan_mm(from, to)
    s = [start_on || from, from].max
    e = [end_on || to, to].min
    return 0.0 if s > e
    total = 0.0
    d = s
    while d <= e
      last = [d.end_of_month, e].min
      total += ((last - d).to_i + 1).to_f / d.end_of_month.day
      d = last + 1
    end
    (total * rate / 100.0).round(2)
  end

  # from~to 사이 실적 M/M (Redmine 사용자 연결 시 이 프로젝트 소요시간)
  def actual_mm(from, to)
    return nil unless user_id
    (TimeEntry.where(project_id: project_id, user_id: user_id, spent_on: from..to).sum(:hours) / HOURS_PER_MM).round(2)
  end
end
