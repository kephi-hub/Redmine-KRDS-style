# 산출물 관리 — 산출물(단계별·첨부·자동 생성·검수용 일괄 다운로드), 변경요청, 프로그램 목록, 회의록, 이슈·위험
# - 자동 생성은 다른 플러그인(qa_trace·menu_tree·db_manage·ops_asset·glossary)의 엑셀을 그대로 씀 (PmKit::AutoDocs)
# - 프로젝트 메뉴 대분류: 산출물(산출물·회의록·이슈·위험), 설계(요구사항 안 변경요청 탭), 개발(프로그램 목록) — krds_ui MenuGroups
require 'csv'
require_relative 'lib/pm_kit/error'
require_relative 'lib/pm_kit/sheet'
require_relative 'lib/pm_kit/auto_docs'
require_relative 'lib/pm_kit/standard'
require_relative 'lib/pm_kit/package'
require_relative 'lib/pm_kit/suggest'
require_relative 'lib/pm_kit/importer'

Redmine::Plugin.register :pm_docs do
  name '산출물 관리'
  author 'kephi-hub'
  description '산출물(단계별·자동 생성·일괄 다운로드), 변경요청, 프로그램 목록, 회의록, 이슈·위험 관리대장'
  version '1.0.0'
  url 'https://github.com/kephi-hub/Redmine-KRDS-style'
  requires_redmine version_or_higher: '6.0'

  project_module :deliverables do
    permission :view_deliverables, { pm_deliverables: [:index, :show, :generate, :package] }, read: true
    permission :manage_deliverables, { pm_deliverables: [:new, :create, :edit, :update, :destroy, :attach, :seed] }, require: :member
  end
  project_module :change_requests do
    permission :view_change_requests, { pm_change_requests: [:index, :show, :export] }, read: true
    permission :manage_change_requests, { pm_change_requests: [:new, :create, :edit, :update, :destroy, :make_issue] }, require: :member
    permission :approve_change_requests, { pm_change_requests: [:decide] }, require: :member
  end
  project_module :programs do
    permission :view_programs, { pm_programs: [:index, :show, :export] }, read: true
    permission :manage_programs, { pm_programs: [:new, :create, :edit, :update, :destroy, :from_menus, :suggest, :import] }, require: :member
  end
  project_module :meetings do
    permission :view_meetings, { pm_meetings: [:index, :show] }, read: true
    permission :manage_meetings, { pm_meetings: [:new, :create, :edit, :update, :destroy] }, require: :member
  end
  project_module :risks do
    permission :view_risks, { pm_risks: [:index, :show, :export] }, read: true
    permission :manage_risks, { pm_risks: [:new, :create, :edit, :update, :destroy] }, require: :member
  end

  menu :project_menu, :deliverables, { controller: 'pm_deliverables', action: 'index' }, caption: :label_pm_deliverables, param: :project_id
  menu :project_menu, :change_requests, { controller: 'pm_change_requests', action: 'index' }, caption: :label_pm_crs, param: :project_id
  menu :project_menu, :programs, { controller: 'pm_programs', action: 'index' }, caption: :label_pm_programs, param: :project_id
  menu :project_menu, :meetings, { controller: 'pm_meetings', action: 'index' }, caption: :label_pm_meetings, param: :project_id
  menu :project_menu, :risks, { controller: 'pm_risks', action: 'index' }, caption: :label_pm_risks, param: :project_id
end

unless Project.reflect_on_association(:pm_deliverables)
  Project.has_many :pm_deliverables, dependent: :destroy
  Project.has_many :pm_change_requests, dependent: :destroy
  Project.has_many :pm_programs, dependent: :delete_all
  Project.has_many :pm_meetings, dependent: :delete_all
  Project.has_many :pm_risks, dependent: :delete_all
end
# 일감을 지우면 위험의 일감 번호를 비우고 변경요청의 일감 연결을 지움
Issue.has_many :pm_risks, dependent: :nullify unless Issue.reflect_on_association(:pm_risks)
Issue.has_many :pm_cr_issue_links, -> { where(target_type: 'issue') }, class_name: 'PmCrLink', foreign_key: :target_id, dependent: :delete_all unless Issue.reflect_on_association(:pm_cr_issue_links)
if Redmine::Plugin.installed?(:menu_tree)
  MenuItem.has_many :pm_programs, dependent: :nullify unless MenuItem.reflect_on_association(:pm_programs)
end
