# 회의록 — decisions: ["결정 1", …], actions: [{ 'title', 'assignee_id', 'due_on', 'issue_id' }] (JSON)
class PmMeeting < ApplicationRecord
  belongs_to :project
  belongs_to :author, class_name: 'User', optional: true

  validates :title, presence: true, length: { maximum: 200 }
  validates :held_at, presence: true
  validates :place, length: { maximum: 120 }

  scope :sorted, -> { order(held_at: :desc, id: :desc) }

  def decision_list
    list = JSON.parse(decisions.to_s) rescue []
    list.is_a?(Array) ? list.map(&:to_s) : []
  end

  def action_list
    list = JSON.parse(actions.to_s) rescue []
    list.is_a?(Array) ? list.select { |a| a.is_a?(Hash) } : []
  end
end
