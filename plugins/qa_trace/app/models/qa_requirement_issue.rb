class QaRequirementIssue < ApplicationRecord
  belongs_to :qa_requirement
  belongs_to :issue
end
