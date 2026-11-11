# 테스트 회차 (예: 1차 통합테스트) — 만들 때 대상 케이스마다 '미수행' 결과 줄이 생김
class QaTestRun < ApplicationRecord
  STATUSES = %w(open closed).freeze

  belongs_to :project
  has_many :qa_test_results, dependent: :delete_all

  validates :name, presence: true, length: { maximum: 100 }
  validates :kind, inclusion: { in: QaTestCase::KINDS }, allow_blank: true
  validates :status, inclusion: { in: STATUSES }
  validate :period

  scope :sorted, -> { order(Arel.sql('start_on IS NULL'), start_on: :desc, id: :desc) }

  def period
    errors.add(:end_on, :greater_than_start_date) if start_on && end_on && end_on < start_on
  end

  def open?
    status == 'open'
  end

  # 대상 케이스 맞추기: 사용 중이고 종류가 맞는 케이스 중 아직 없는 것만 추가 (기존 결과는 그대로)
  def sync_cases
    cases = QaTestCase.where(project_id: project_id).active
    cases = cases.where(kind: kind) if kind.present?
    have = qa_test_results.pluck(:qa_test_case_id)
    added = 0
    cases.where.not(id: have).pluck(:id).each do |cid|
      QaTestResult.create!(qa_test_run_id: id, qa_test_case_id: cid)
      added += 1
    end
    added
  end

  # { 'pass' => 3, 'fail' => 1, … }
  def counts
    @counts ||= qa_test_results.group(:result).count
  end

  def total
    counts.values.sum
  end

  def done_ratio
    t = total
    t.zero? ? 0 : ((t - counts['none'].to_i) * 100 / t)
  end
end
