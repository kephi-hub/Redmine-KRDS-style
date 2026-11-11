# 용어사전 용어 — project_id 가 비어 있으면 전사 공통, 있으면 그 프로젝트 전용
class GlossaryTerm < ApplicationRecord
  include Redmine::SafeAttributes
  belongs_to :project, optional: true
  belongs_to :author, class_name: 'User', optional: true
  belongs_to :updated_by, class_name: 'User', optional: true

  ABBR_FORMAT = /\A[A-Za-z][A-Za-z0-9_]*\z/
  COLUMNS = %w(name name_en abbr category data_type data_length definition note).freeze

  safe_attributes(*COLUMNS)

  before_validation { self.abbr = abbr.to_s.strip.upcase.presence; self.name = name.to_s.strip }
  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { scope: :project_id, case_sensitive: false }
  validates :abbr, length: { maximum: 100 }, format: { with: ABBR_FORMAT, allow_blank: true }
  validates :name_en, length: { maximum: 200 }
  validates :category, :data_type, length: { maximum: 60 }
  validates :data_length, length: { maximum: 30 }

  scope :common, -> { where(project_id: nil) }
  scope :sorted, -> { order(:name) }
  # 프로젝트 화면: 그 프로젝트 용어 + 공통 용어
  scope :for_project, ->(project) { where(project_id: [nil, project&.id].uniq) }

  def common?
    project_id.nil?
  end

  def type_label
    [data_type, (data_length.present? ? "(#{data_length})" : nil)].compact.join
  end

  # 같은 이름이 프로젝트와 공통에 모두 있으면 프로젝트 용어 우선
  def self.lookup(project, name)
    for_project(project).where('LOWER(name) = ?', name.to_s.strip.downcase).order(Arel.sql('project_id IS NULL')).first
  end
end
