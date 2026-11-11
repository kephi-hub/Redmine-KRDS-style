# 회차 × 케이스 결과 — 불합격이면 결함 일감 연결
class QaTestResult < ApplicationRecord
  RESULTS = %w(none pass fail hold skip).freeze

  belongs_to :qa_test_run
  belongs_to :qa_test_case
  belongs_to :user, optional: true
  belongs_to :issue, optional: true

  validates :result, inclusion: { in: RESULTS }

  # 결함 일감이 해결(종료)됐는데 결과가 아직 불합격 → 다시 테스트할 차례
  def retest?
    result == 'fail' && issue&.closed?
  end
end
