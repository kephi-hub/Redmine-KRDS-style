class RepoExportLog < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :repository, optional: true
  belongs_to :project, optional: true
  scope :recent, -> { order(created_at: :desc, id: :desc) }
end
