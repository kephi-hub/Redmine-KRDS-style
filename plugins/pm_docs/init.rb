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
require_relative 'lib/pm_kit/dashboard'
require_relative 'lib/pm_kit/status_suggest'
require_relative 'lib/pm_kit/hooks'
require_relative 'lib/pm_kit/sla'
require_relative 'lib/pm_kit/report'
require_relative 'lib/pm_kit/portfolio'
require_relative 'lib/pm_kit/closing'

Redmine::Plugin.register :pm_docs do
  name '산출물 관리'
  author 'kephi-hub'
  description '산출물(단계별·자동 생성·일괄 다운로드), 변경요청, 프로그램 목록, 회의록, 이슈·위험, 감리 지적사항, 투입 인력, 보안 취약점 진단, 주간·월간 보고서, 일정 기준선, 준공 체크리스트'
  version '1.4.0'
  url 'https://github.com/kephi-hub/Redmine-KRDS-style'
  requires_redmine version_or_higher: '6.0'

  project_module :deliverables do
    permission :view_deliverables, { pm_deliverables: [:index, :show, :generate, :package] }, read: true
    permission :manage_deliverables, { pm_deliverables: [:new, :create, :edit, :update, :destroy, :attach, :seed, :review] }, require: :member
    # 승인·반려·되돌림 (검토 요청·제출은 산출물 관리 권한)
    permission :approve_deliverables, { pm_deliverables: [:review] }, require: :member
  end
  project_module :change_requests do
    permission :view_change_requests, { pm_change_requests: [:index, :show, :export] }, read: true
    permission :manage_change_requests, { pm_change_requests: [:new, :create, :edit, :update, :destroy, :make_issue] }, require: :member
    permission :approve_change_requests, { pm_change_requests: [:decide] }, require: :member
  end
  project_module :programs do
    permission :view_programs, { pm_programs: [:index, :show, :export] }, read: true
    permission :manage_programs, { pm_programs: [:new, :create, :edit, :update, :destroy, :from_menus, :suggest, :status_suggest, :import] }, require: :member
  end
  project_module :meetings do
    permission :view_meetings, { pm_meetings: [:index, :show] }, read: true
    permission :manage_meetings, { pm_meetings: [:new, :create, :edit, :update, :destroy] }, require: :member
  end
  project_module :risks do
    permission :view_risks, { pm_risks: [:index, :show, :export] }, read: true
    permission :manage_risks, { pm_risks: [:new, :create, :edit, :update, :destroy] }, require: :member
  end
  project_module :audits do
    permission :view_audits, { pm_audits: [:index, :show, :export] }, read: true
    permission :manage_audits, { pm_audits: [:new, :create, :edit, :update, :destroy, :import], pm_audit_rounds: [:new, :create, :edit, :update, :destroy] }, require: :member
  end
  # 투입 인력은 계정·소속 등 개인 정보가 있어 보기 권한도 따로
  project_module :staff do
    permission :view_staff, { pm_staffs: [:index, :export] }, read: true
    permission :manage_staff, { pm_staffs: [:new, :create, :edit, :update, :destroy] }, require: :member
  end
  project_module :sec_scans do
    permission :view_sec_scans, { pm_sec_scans: [:index, :show, :export] }, read: true
    permission :manage_sec_scans, { pm_sec_scans: [:new, :create, :edit, :update, :destroy, :bulk] }, require: :member
  end
  project_module :pm_reports do
    permission :view_pm_reports, { pm_reports: [:index, :export] }, read: true
  end
  project_module :baselines do
    permission :view_baselines, { pm_baselines: [:index, :show, :export] }, read: true
    permission :manage_baselines, { pm_baselines: [:create, :destroy] }, require: :member
  end
  project_module :closing do
    permission :view_closing, { pm_closing: [:index, :export] }, read: true
    permission :manage_closing, { pm_closing: [:check] }, require: :member
  end

  menu :project_menu, :deliverables, { controller: 'pm_deliverables', action: 'index' }, caption: :label_pm_deliverables, param: :project_id
  menu :project_menu, :change_requests, { controller: 'pm_change_requests', action: 'index' }, caption: :label_pm_crs, param: :project_id
  menu :project_menu, :programs, { controller: 'pm_programs', action: 'index' }, caption: :label_pm_programs, param: :project_id
  menu :project_menu, :meetings, { controller: 'pm_meetings', action: 'index' }, caption: :label_pm_meetings, param: :project_id
  menu :project_menu, :risks, { controller: 'pm_risks', action: 'index' }, caption: :label_pm_risks, param: :project_id
  menu :project_menu, :audits, { controller: 'pm_audits', action: 'index' }, caption: :label_pm_audits, param: :project_id
  menu :project_menu, :staff, { controller: 'pm_staffs', action: 'index' }, caption: :label_pm_staffs, param: :project_id
  menu :project_menu, :sec_scans, { controller: 'pm_sec_scans', action: 'index' }, caption: :label_pm_sec_scans, param: :project_id
  menu :project_menu, :pm_reports, { controller: 'pm_reports', action: 'index' }, caption: :label_pm_reports, param: :project_id
  menu :project_menu, :baselines, { controller: 'pm_baselines', action: 'index' }, caption: :label_pm_baselines, param: :project_id
  menu :project_menu, :closing, { controller: 'pm_closing', action: 'index' }, caption: :label_pm_closing, param: :project_id
end

# 전체 프로젝트 현황 (PMO) — 상단 공통 메뉴 · 초기화면 메뉴
Redmine::MenuManager.map :top_menu do |menu|
  menu.push :pm_portfolio, { controller: 'pm_portfolio', action: 'index' }, caption: :label_pm_portfolio, after: :projects, if: ->(_) { User.current.logged? }
end
Redmine::MenuManager.map :application_menu do |menu|
  menu.push :pm_portfolio, { controller: 'pm_portfolio', action: 'index' }, caption: :label_pm_portfolio, after: :projects, if: ->(_) { User.current.logged? }
end

unless Project.reflect_on_association(:pm_deliverables)
  Project.has_many :pm_deliverables, dependent: :destroy
  Project.has_many :pm_change_requests, dependent: :destroy
  Project.has_many :pm_programs, dependent: :delete_all
  Project.has_many :pm_meetings, dependent: :delete_all
  Project.has_many :pm_audits, dependent: :delete_all
  Project.has_many :pm_audit_rounds, dependent: :delete_all
  Project.has_many :pm_staffs, dependent: :delete_all
  Project.has_many :pm_sec_items, dependent: :delete_all
  Project.has_many :pm_sec_scans, dependent: :delete_all
  Project.has_many :pm_risks, dependent: :delete_all
  Project.has_many :pm_baselines, dependent: :destroy
  Project.has_many :pm_closing_checks, dependent: :delete_all
end
# 일감을 지우면 위험의 일감 번호를 비우고 변경요청의 일감 연결을 지움
Issue.has_many :pm_risks, dependent: :nullify unless Issue.reflect_on_association(:pm_risks)
Issue.has_many :pm_audits, dependent: :nullify unless Issue.reflect_on_association(:pm_audits)
PmDeliverable.has_many :pm_audits, dependent: :nullify unless PmDeliverable.reflect_on_association(:pm_audits)
PmProgram.has_many :pm_sec_items, dependent: :nullify unless PmProgram.reflect_on_association(:pm_sec_items)
# SR 일감: 완료 기한을 비워 두면 긴급도로 자동 (PmKit::Sla)
unless Issue.instance_variable_get(:@pm_sla_hooked)
  Issue.before_validation { PmKit::Sla.fill_due(self) }
  Issue.instance_variable_set(:@pm_sla_hooked, true)
end
Issue.has_many :pm_cr_issue_links, -> { where(target_type: 'issue') }, class_name: 'PmCrLink', foreign_key: :target_id, dependent: :delete_all unless Issue.reflect_on_association(:pm_cr_issue_links)
if Redmine::Plugin.installed?(:menu_tree)
  MenuItem.has_many :pm_programs, dependent: :nullify unless MenuItem.reflect_on_association(:pm_programs)
end
