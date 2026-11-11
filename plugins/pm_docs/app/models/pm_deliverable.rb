# 산출물 한 건 — 단계·상태·버전·마감, 첨부(Redmine 첨부, 올린 순서가 버전 이력), 자동 생성 종류(auto_kind)
class PmDeliverable < ApplicationRecord
  PHASES = %w(start analysis design build test transition close).freeze
  STATUSES = %w(none writing review approved submitted).freeze

  belongs_to :project
  belongs_to :owner, class_name: 'User', optional: true
  acts_as_attachable view_permission: :view_deliverables, edit_permission: :manage_deliverables, delete_permission: :manage_deliverables

  validates :name, presence: true, length: { maximum: 150 }
  validates :phase, inclusion: { in: PHASES }
  validates :status, inclusion: { in: STATUSES }
  validates :code, length: { maximum: 30 }
  validates :version, length: { maximum: 20 }
  validates :auto_kind, inclusion: { in: ->(_) { PmKit::AutoDocs::KINDS.keys } }, allow_blank: true

  scope :sorted, -> { order(Arel.sql("CASE phase #{PHASES.each_with_index.map { |p, i| "WHEN '#{p}' THEN #{i}" }.join(' ')} END"), :position, :id) }

  def done?
    %w(approved submitted).include?(status)
  end

  def late?(today = Date.current)
    due_on && due_on < today && !done?
  end

  def latest_attachment
    attachments.max_by { |a| [a.created_on, a.id] }
  end

  def to_s
    name
  end
end
