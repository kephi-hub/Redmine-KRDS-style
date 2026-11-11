# 운영 관리 — 인프라 자산 · 시스템 스케줄러 · 점검·장애 · 연계 인터페이스
# - 자산: 서버·도메인·SSL 인증서·라이선스·클라우드·장비, 만료일(화면 알림 + 메일 알림 rake), 공용 자산(관리 > 자산 대장) ↔ 프로젝트 연결
# - 스케줄러: cron·Spring·Quartz·Windows·Jenkins·DB 잡, 일정 한국어 풀이·다음 실행, 24시간 타임라인(몰림·겹침),
#   crontab 붙여넣기·DB 잡(db_manage)·Jenkins 주기 빌드(jenkins_deploy) 가져오기, 배치 정의서 엑셀
# - 점검·장애: 장애 기록(중단 시간 자동·일감 연결), 점검표 양식·정기점검, 월간 보고서(배포·DB 구조 변경 포함) 엑셀
# - 인터페이스: 연계 정의(방향·방식·주기·데이터·주소·담당), 구성도(Mermaid · draw.io), 인터페이스 정의서 엑셀
require_relative 'lib/ops_kit/cron'
require_relative 'lib/ops_kit/sheet'
require_relative 'lib/ops_kit/report'
require_relative 'lib/ops_kit/importer'
require_relative 'lib/ops_kit/notifier'
require_relative 'lib/ops_kit/diagram'

Redmine::Plugin.register :ops_asset do
  name '운영 관리'
  author 'kephi-hub'
  description '인프라 자산 대장, 시스템 스케줄러, 점검·장애 이력·월간 보고서, 연계 인터페이스·구성도'
  version '1.0.0'
  url 'https://github.com/kephi-hub/Redmine-KRDS-style'
  requires_redmine version_or_higher: '6.0'

  project_module :ops_assets do
    permission :view_ops_assets, { ops_assets: [:index, :export] }, read: true
    permission :manage_ops_assets, { ops_assets: [:new, :create, :edit, :update, :destroy, :link, :unlink] }, require: :member
  end
  project_module :ops_schedules do
    permission :view_ops_schedules, { ops_schedules: [:index, :show, :timeline, :export, :preview] }, read: true
    permission :manage_ops_schedules, { ops_schedules: [:new, :create, :edit, :update, :destroy, :import] }, require: :member
  end
  project_module :ops_logs do
    permission :view_ops_logs, { ops_incidents: [:index, :show], ops_checks: [:index, :show], ops_reports: [:index] }, read: true
    permission :manage_ops_logs, { ops_incidents: [:new, :create, :edit, :update, :destroy], ops_checks: [:new, :create, :edit, :update, :destroy],
                                   ops_check_templates: [:new, :create, :edit, :update, :destroy] }, require: :member
  end
  project_module :ops_interfaces do
    permission :view_ops_interfaces, { ops_interfaces: [:index, :show, :diagram, :export] }, read: true
    permission :manage_ops_interfaces, { ops_interfaces: [:new, :create, :edit, :update, :destroy] }, require: :member
  end

  menu :project_menu, :ops_assets, { controller: 'ops_assets', action: 'index' }, caption: :label_oa_assets, after: :qa_tests, param: :project_id
  menu :project_menu, :ops_schedules, { controller: 'ops_schedules', action: 'index' }, caption: :label_oa_schedules, after: :ops_assets, param: :project_id
  menu :project_menu, :ops_incidents, { controller: 'ops_incidents', action: 'index' }, caption: :label_oa_logs, after: :ops_schedules, param: :project_id
  menu :project_menu, :ops_interfaces, { controller: 'ops_interfaces', action: 'index' }, caption: :label_oa_interfaces, after: :ops_incidents, param: :project_id
end

Redmine::MenuManager.map :admin_menu do |menu|
  menu.push :admin_ops_assets, { controller: 'admin_ops_assets', action: 'index' }, caption: :label_oa_admin_assets,
            after: :db_servers, html: { class: 'icon icon-package' }, icon: 'package'
end

unless Project.reflect_on_association(:ops_schedules)
  # 프로젝트 삭제 시 프로젝트 자산·스케줄·점검·장애·인터페이스도 함께 (공용 자산은 연결만 풀림)
  Project.has_many :ops_assets, dependent: :destroy
  Project.has_many :ops_asset_links, dependent: :delete_all
  Project.has_many :ops_schedules, dependent: :destroy
  Project.has_many :ops_interfaces, dependent: :destroy
  Project.has_many :ops_incidents, dependent: :delete_all
  Project.has_many :ops_checks, dependent: :delete_all
  Project.has_many :ops_check_templates, dependent: :delete_all
end
# 일감을 지우면 장애 기록의 일감 번호만 비움
Issue.has_many :ops_incidents, dependent: :nullify unless Issue.reflect_on_association(:ops_incidents)
