# 요구사항 한 건 — ID 는 공공 표준 분류 접두어 + 번호 (예: SFR-001), 비워 두면 자동
class QaRequirement < ApplicationRecord
  # 공공 정보화사업 제안요청서 요구사항 분류
  CATEGORIES = %w(SFR PER SIR DAR TER SER QUR COR PMR PSR).freeze
  CATEGORY_NAMES = { 'SFR' => '기능', 'PER' => '성능', 'SIR' => '인터페이스', 'DAR' => '데이터', 'TER' => '테스트', 'SER' => '보안',
                     'QUR' => '품질', 'COR' => '제약사항', 'PMR' => '프로젝트 관리', 'PSR' => '프로젝트 지원' }.freeze
  PRIORITIES = %w(high normal low).freeze
  STATUSES = %w(received confirmed changed deleted).freeze
  TRACKED = %w(code category name description source priority status parent_id).freeze

  belongs_to :project
  belongs_to :parent, class_name: 'QaRequirement', optional: true
  has_many :children, class_name: 'QaRequirement', foreign_key: :parent_id, dependent: :nullify
  has_many :qa_requirement_menus, dependent: :delete_all
  has_many :menu_items, through: :qa_requirement_menus
  has_many :qa_requirement_issues, dependent: :delete_all
  has_many :issues, through: :qa_requirement_issues
  has_many :qa_case_requirements, dependent: :delete_all
  has_many :qa_requirement_logs, -> { order(created_at: :desc, id: :desc) }, dependent: :delete_all

  validates :name, presence: true, length: { maximum: 200 }
  validates :category, inclusion: { in: CATEGORIES }
  validates :priority, inclusion: { in: PRIORITIES }
  validates :status, inclusion: { in: STATUSES }
  validates :code, presence: true, length: { maximum: 30 }, format: { with: /\A[A-Za-z0-9][A-Za-z0-9_.\-]*\z/ },
                   uniqueness: { scope: :project_id, case_sensitive: false }
  validates :source, length: { maximum: 200 }
  validate :parent_in_project

  before_validation :fill_code

  scope :sorted, -> { order(:category, :code) }
  scope :alive, -> { where.not(status: 'deleted') }

  def self.category_order(cat)
    CATEGORIES.index(cat) || 99
  end

  # 같은 분류의 다음 번호 (SFR-001 → SFR-002)
  def self.next_code(project, category)
    nums = where(project_id: project.id).where('code LIKE ?', "#{category}-%").pluck(:code).map { |c| c[/\A#{category}-(\d+)/, 1].to_i }
    format('%s-%03d', category, (nums.max || 0) + 1)
  end

  def fill_code
    self.code = code.to_s.strip.upcase.presence
    self.name = name.to_s.strip
    self.category ||= code.to_s[/\A([A-Z]{3})-/, 1] if code
    self.code ||= self.class.next_code(project, category) if project && CATEGORIES.include?(category)
  end

  def parent_in_project
    return unless parent
    errors.add(:parent_id, :invalid) if parent.project_id != project_id || parent.id == id
  end

  def deleted?
    status == 'deleted'
  end

  # 바뀐 칸을 변경 이력으로 (메뉴·일감 연결 변경은 extra 로 함께)
  def log_changes(user, before, extra = [])
    details = TRACKED.filter_map { |f| [f, before[f], self[f]] if before.key?(f) && before[f].to_s != self[f].to_s } + extra
    return if details.empty?
    QaRequirementLog.create!(qa_requirement_id: id, user_id: user&.id, details: details.to_json)
  end

  def to_s
    "#{code} #{name}"
  end
end
