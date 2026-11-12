# 준공 체크리스트의 수동 항목 확인 기록 (자동 항목은 PmKit::Closing 이 그때그때 계산)
class PmClosingCheck < ApplicationRecord
  belongs_to :project
  belongs_to :user, optional: true
end
