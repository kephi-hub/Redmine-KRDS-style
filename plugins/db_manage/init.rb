# DB 관리 — 관리자가 DB 서버 접속정보를 등록하고(Jenkins 서버와 같은 방식), 프로젝트에서 스키마를 조회
# - 관리 > DB 서버 : DB 종류(MariaDB·MySQL, PostgreSQL / MS SQL·Oracle 준비 중)·주소·계정·비밀번호(암호화 저장), 연결 시험
# - 프로젝트 > 설정 > DB : 개발DB·운영DB 등 이 프로젝트에서 쓸 DB 서버·스키마 지정
# - 프로젝트 > DB : 테이블·컬럼·키 조회, 테이블 정의서(엑셀), 개발/운영 비교, 용어사전 점검
# - 1.1.0 : DB 서버 개발/운영 구분(프로젝트 연결 기본값), 등록·편집 화면에서 저장 전 연결 시험
# 원격 DB 에는 읽기 전용 세션으로 접속해 메타데이터만 읽음 (데이터 조회·변경 SQL 없음)
require_relative 'lib/db_manage/connector'
require_relative 'lib/db_manage/xlsx'
require_relative 'lib/db_manage/analysis'
require_relative 'lib/db_manage/project_settings_patch'

Redmine::Plugin.register :db_manage do
  name 'DB 관리'
  author 'kephi-hub'
  description 'DB 서버 접속정보 관리, 프로젝트 DB 스키마 조회·테이블 정의서·개발/운영 비교·용어 점검'
  version '1.1.0'
  url 'https://github.com/kephi-hub/Redmine-KRDS-style'
  requires_redmine version_or_higher: '6.0'

  project_module :db_manage do
    permission :view_db_schema, { db_schemas: [:index, :table, :export, :compare, :check] }, read: true
    permission :manage_db_links, { projects: :settings, db_links: [:new, :create, :edit, :update, :destroy] }, require: :member
  end

  menu :project_menu, :db_schemas, { controller: 'db_schemas', action: 'index' },
       caption: :label_db_manage, after: :deploys, param: :project_id
end

# 관리 메뉴 (Redmine 기본 아이콘 사용)
Redmine::MenuManager.map :admin_menu do |menu|
  menu.push :db_servers, { controller: 'db_servers', action: 'index' },
            caption: :label_db_server_plural, after: :jenkins_servers,
            html: { class: 'icon icon-table-multiple' }, icon: 'table-multiple'
end

ProjectsHelper.prepend(DbManage::ProjectSettingsPatch) unless ProjectsHelper.ancestors.include?(DbManage::ProjectSettingsPatch)
Project.has_many :db_links, dependent: :destroy unless Project.reflect_on_association(:db_links)

# 비밀번호가 로그에 남지 않게
Rails.application.config.filter_parameters += [:password]
