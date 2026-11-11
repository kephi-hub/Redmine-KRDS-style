# 프로그램 목록 한 줄 — 프로그램 ID, 유형, 메뉴(화면), 소스 경로(여러 줄), 개발자, 진척
class PmProgram < ApplicationRecord
  KINDS = %w(screen popup batch api common report).freeze
  STATUSES = %w(todo dev done tested).freeze

  belongs_to :project
  belongs_to :developer, class_name: 'User', optional: true
  belongs_to :menu_item, optional: true

  validates :code, presence: true, length: { maximum: 60 }, uniqueness: { scope: :project_id, case_sensitive: false }
  validates :name, presence: true, length: { maximum: 150 }
  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validate :menu_in_project

  before_validation { self.code = code.to_s.strip.presence; self.name = name.to_s.strip }

  scope :sorted, -> { order(:code) }

  def menu_in_project
    errors.add(:menu_item_id, :invalid) if menu_item && menu_item.project_id != project_id
  end

  def paths
    source_paths.to_s.lines.map(&:strip).reject(&:empty?)
  end
end
