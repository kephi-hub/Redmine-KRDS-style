# 요구사항 변경 이력 — details: [[칸, 이전 값, 새 값], …] (JSON)
class QaRequirementLog < ApplicationRecord
  belongs_to :qa_requirement
  belongs_to :user, optional: true

  def entries
    JSON.parse(details.to_s)
  rescue JSON::ParserError
    []
  end
end
