class QaRequirementMenu < ApplicationRecord
  belongs_to :qa_requirement
  belongs_to :menu_item
end
