# DB 관리 — 관리자가 DB 서버 접속정보를 등록하고(Jenkins 서버와 같은 방식), 프로젝트에서 스키마를 조회
# - 관리 > DB 서버 : DB 종류(MariaDB·MySQL, PostgreSQL / MS SQL·Oracle 준비 중)·주소·계정·비밀번호(암호화 저장), 연결 시험
# - 프로젝트 > 설정 > DB : 개발DB·운영DB 등 이 프로젝트에서 쓸 DB 서버·스키마 지정
# - 프로젝트 > DB : 테이블·컬럼·키 조회, 테이블 정의서(엑셀), 개발/운영 비교, 용어사전 점검
# - 1.1.0 : DB 서버 개발/운영 구분(프로젝트 연결 기본값), 등록·편집 화면에서 저장 전 연결 시험
# - 1.2.0 : SSH 터널(예: Redmine → WEB 서버 → 운영 DB), 비밀번호·개인키 인증, 서버 지문 확인
# - 1.3.0 : 종류 탭(테이블·뷰·구체화 뷰·함수·프로시저·트리거·DB 잡·시퀀스 — DB 종류마다 다름), 객체 상세(정의 SQL), 숫자 요약,
#           객체 비교·정의서 시트 추가, 프로젝트 DB 연결의 운영 표시는 DB 서버 구분을 따름(체크박스 제거)
# - 1.4.0 : ERD (Mermaid — krds_ui 플러그인에 포함, 인터넷 불필요) 보기·테이블 선택·추정 관계, .md/.mmd/SVG/PNG 내려받기,
#           위키·일감 본문의 ```mermaid 블록을 그림으로
# - 1.5.0 : DB 종류별 처리 분리(Dialect), 인덱스 정보, 화면 캐시(10분·새로 고침), 다단계 SSH(최대 3대), 용어 점검(설명 누락·불일치), ERD draw.io
# - 1.6.0 : 구조 변경 이력(저장본 비교, rake 자동 저장), SQL 조회(조회 문장만·읽기 전용·시간/건수 제한·실행 기록, 운영 DB 별도 권한)
# 원격 DB 에는 읽기 전용 세션으로 접속해 메타데이터만 읽음 (데이터 조회·변경 SQL 없음)
require_relative 'lib/db_manage/dialect_base'
require_relative 'lib/db_manage/dialect_mysql'
require_relative 'lib/db_manage/dialect_postgresql'
require_relative 'lib/db_manage/connector'
require_relative 'lib/db_manage/sql_guard'
require_relative 'lib/db_manage/tunnel'
require_relative 'lib/db_manage/analysis'
require_relative 'lib/db_manage/erd'
require_relative 'lib/db_manage/project_settings_patch'

Redmine::Plugin.register :db_manage do
  name 'DB 관리'
  author 'kephi-hub'
  description 'DB 서버 접속정보 관리, 프로젝트 DB 스키마 조회·테이블 정의서·개발/운영 비교·용어 점검'
  version '1.6.0'
  url 'https://github.com/kephi-hub/Redmine-KRDS-style'
  requires_redmine version_or_higher: '6.0'

  project_module :db_manage do
    permission :view_db_schema, { db_schemas: [:index, :table, :object, :export, :compare, :check, :erd, :history, :history_diff] }, read: true
    permission :manage_db_links, { projects: :settings, db_links: [:new, :create, :edit, :update, :destroy], db_schemas: [:save_history, :query_log] }, require: :member
    # SQL 조회: 개발 DB 와 운영 DB 권한을 따로 (운영은 기본으로 아무 역할에도 주지 않음)
    permission :run_db_query, { db_schemas: [:query] }, require: :member
    permission :run_db_query_production, { db_schemas: [:query] }, require: :member
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
DbLink.has_many :db_snapshots, dependent: :delete_all unless DbLink.reflect_on_association(:db_snapshots)

# 비밀번호가 로그에 남지 않게
Rails.application.config.filter_parameters += [:password, :ssh_password, :ssh_private_key, :ssh_passphrase]
