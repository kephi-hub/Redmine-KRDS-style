# 프로그램 목록 한 줄 — 프로그램 ID, 유형, 처리 구분, 메뉴(화면), 소스 경로(여러 줄), 개발자, 진척
# 화면 1개에 기능(서버 처리가 있는 버튼) 단위 프로그램 여러 개 — 예: 목록 조회 · 엑셀 다운로드 / 등록 · 수정 · 삭제
class PmProgram < ApplicationRecord
  KINDS = %w(screen popup batch api common report).freeze
  STATUSES = %w(todo dev done tested).freeze
  ACTIONS = %w(select insert update delete download upload print approve etc).freeze
  # 기능 단위 프로그램 ID 접미어: 화면 ID-S(조회) -I(등록) -U(수정) -D(삭제) -X(다운로드) -F(업로드) -P(출력) -A(승인) -E(기타)
  SUFFIX = { 'select' => 'S', 'insert' => 'I', 'update' => 'U', 'delete' => 'D', 'download' => 'X', 'upload' => 'F', 'print' => 'P', 'approve' => 'A', 'etc' => 'E' }.freeze
  # [메뉴 구조도에서 만들기 — 기능 단위] 화면 유형별 기본 기능 [처리, 이름]
  DEFAULT_FUNCS = {
    'list' => [%w(select 목록\ 조회), %w(download 엑셀\ 다운로드)],
    'detail' => [%w(select 상세\ 조회)],
    'form' => [%w(insert 등록), %w(update 수정), %w(delete 삭제)],
    'popup' => [%w(select 조회)], 'tab' => [%w(select 조회)], 'link' => []
  }.freeze

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

  def action_list
    actions.to_s.split(',') & ACTIONS
  end

  def action_list=(list)
    self.actions = (ACTIONS & Array(list).map(&:to_s)).join(',').presence
  end

  # 트리에서 [+ 프로그램] 으로 추가할 때 ID 자동: 화면 ID(없으면 그 화면 프로그램의 PGM-nnn, 그것도 없으면 새 PGM-nnn) + 처리 접미어
  # 같은 ID 가 있으면 -2, -3 … (예: SCR-010-S, SCR-010-S-2)
  def self.next_code(project, menu, action)
    codes = where(project_id: project.id).pluck(:code).map(&:upcase).to_set
    base = menu&.screen_id.presence
    base ||= where(project_id: project.id, menu_item_id: menu.id).pluck(:code).map { |c| c[/\A(PGM-\d+)/, 1] }.compact.first if menu
    base ||= format('PGM-%03d', (where(project_id: project.id).where('code LIKE ?', 'PGM-%').pluck(:code).map { |c| c[/\APGM-(\d+)/, 1].to_i }.max || 0) + 1)
    code = "#{base}-#{SUFFIX[action] || 'E'}"
    n = 1
    code = "#{base}-#{SUFFIX[action] || 'E'}-#{n += 1}" while codes.include?(code.upcase)
    code
  end

  # 화면 유형별 기본 기능 (유형이 없으면 조회)
  def self.default_funcs(screen_type)
    DEFAULT_FUNCS.fetch(screen_type.to_s, [%w(select 조회)])
  end
end
