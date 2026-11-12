# 일정 기준선 — 그 시점의 일감 일정(시작·완료 기한·진척·추정 시간)을 저장해 두고 지금 일정과 비교
class PmBaseline < ApplicationRecord
  belongs_to :project
  belongs_to :author, class_name: 'User', optional: true
  has_many :pm_baseline_items, dependent: :delete_all

  validates :name, presence: true, length: { maximum: 100 }

  scope :recent, -> { order(taken_on: :desc, id: :desc) }

  # 지금 일감 일정으로 기준선 만들기 (보이는 일감이 아니라 프로젝트의 모든 일감 — 비교 기준이므로)
  def self.take!(project, name, user, note = nil)
    issues = Issue.where(project_id: project.id).pluck(:id, :subject, :start_date, :due_date, :done_ratio, :estimated_hours)
    transaction do
      b = create!(project: project, name: name, note: note.presence, author: user, taken_on: User.current.today,
                  issue_count: issues.size, start_on: issues.filter_map { |x| x[2] }.min, end_on: issues.filter_map { |x| x[3] }.max)
      issues.each_slice(500) do |slice|
        PmBaselineItem.insert_all(slice.map { |id, sub, s, d, r, e| { pm_baseline_id: b.id, issue_id: id, subject: sub.to_s.truncate(255), start_date: s, due_date: d, done_ratio: r, estimated_hours: e } })
      end
      b
    end
  end

  # 비교 — { rows: [...], summary: {...} }
  # 행: 기준 일감마다 지금 일정(없으면 삭제됨) + 기준 뒤에 새로 생긴 일감
  def compare(user = User.current)
    base = pm_baseline_items.to_a.index_by(&:issue_id)
    now = Issue.where(project_id: project_id).includes(:status, :tracker, :assigned_to).to_a.index_by(&:id)
    visible = Issue.visible(user).where(project_id: project_id).pluck(:id).to_set
    rows = base.values.map do |b|
      i = now[b.issue_id]
      { id: b.issue_id, issue: i, subject: i&.subject || b.subject, base: b, kind: i ? 'kept' : 'removed',
        start_shift: i && b.start_date && i.start_date ? (i.start_date - b.start_date).to_i : nil,
        due_shift: i && b.due_date && i.due_date ? (i.due_date - b.due_date).to_i : nil }
    end
    rows += now.values.reject { |i| base.key?(i.id) }.map { |i| { id: i.id, issue: i, subject: i.subject, base: nil, kind: 'added' } }
    rows.select! { |r| r[:issue].nil? || visible.include?(r[:id]) }
    cur_end = now.values.filter_map(&:due_date).max
    { rows: rows.sort_by { |r| [-(r[:due_shift] || -9999), r[:id]] },
      summary: { base_end: end_on, now_end: cur_end, end_shift: end_on && cur_end ? (cur_end - end_on).to_i : nil,
                 late: rows.count { |r| r[:due_shift].to_i.positive? }, early: rows.count { |r| r[:due_shift].to_i.negative? },
                 added: rows.count { |r| r[:kind] == 'added' }, removed: rows.count { |r| r[:kind] == 'removed' },
                 max_late: rows.filter_map { |r| r[:due_shift] }.max } }
  end
end
