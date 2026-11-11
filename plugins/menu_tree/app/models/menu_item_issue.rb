class MenuItemIssue < ApplicationRecord
  belongs_to :menu_item
  belongs_to :issue
end
