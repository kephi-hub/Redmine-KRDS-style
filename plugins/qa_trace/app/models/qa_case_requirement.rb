class QaCaseRequirement < ApplicationRecord
  belongs_to :qa_test_case
  belongs_to :qa_requirement
end
