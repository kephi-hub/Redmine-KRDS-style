# 산출물 검토·승인 이력 한 줄 — action: request(검토 요청) approve reject submit reopen edit upload
class PmDeliverableReview < ApplicationRecord
  ACTIONS = %w(request approve reject submit reopen edit upload).freeze

  belongs_to :pm_deliverable
  belongs_to :user, optional: true

  validates :action, inclusion: { in: ACTIONS }

  scope :recent, -> { order(created_at: :desc, id: :desc) }
end
