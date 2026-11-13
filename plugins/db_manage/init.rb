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
# - 1.7.0 : MS SQL Server (tiny_tds) — 테이블·뷰·함수·프로시저·트리거·시퀀스·시노님·에이전트 작업
# - 1.8.0 : Oracle (ruby-oci8, Instant Client) — 테이블·뷰·구체화 뷰·함수·프로시저·패키지·트리거·시퀀스·시노님·스케줄러 작업
# - 1.10.0: 공통코드 정의서(코드 테이블 지정·읽기 전용 조회·엑셀), 테이블 정의서·개인정보 엑셀을 DbManage::Docs 로 (산출물 패키지에서도 사용)
# - 1.9.0 : 개인정보 컬럼(분류·암호화 여부, 이름·설명·용어로 자동 후보, 암호화 누락·DB 에서 사라짐 경고, 엑셀)
# - 1.13.0: 이관에 뷰·구체화 뷰·함수·프로시저·패키지 (의존 순서·재시도, 이관 전 정의 백업)
# - 1.12.0: 이관을 PostgreSQL·MS SQL Server·Oracle 로 확장 (같은 종류끼리, DB 별 엔진 Migrate*)
# - 1.11.0: 이관(MariaDB·MySQL) — 개발 ↔ 운영 테이블 구조·데이터, 미리보기·실행 전 대상 테이블 백업 (이관용 쓰기 계정, 대상별 권한)
# 원격 DB 에는 읽기 전용 세션으로 접속해 메타데이터만 읽음 (이관만 대상 DB 에 씀)
require_relative 'lib/db_manage/dialect_base'
require_relative 'lib/db_manage/dialect_mysql'
require_relative 'lib/db_manage/dialect_postgresql'
require_relative 'lib/db_manage/dialect_mssql'
require_relative 'lib/db_manage/dialect_oracle'
require_relative 'lib/db_manage/connector'
require_relative 'lib/db_manage/sql_guard'
require_relative 'lib/db_manage/tunnel'
require_relative 'lib/db_manage/analysis'
require_relative 'lib/db_manage/privacy'
require_relative 'lib/db_manage/docs'
require_relative 'lib/db_manage/codes'
require_relative 'lib/db_manage/erd'
require_relative 'lib/db_manage/project_settings_patch'
require_relative 'lib/db_manage/migrator'
require_relative 'lib/db_manage/migrate_mysql'
require_relative 'lib/db_manage/migrate_postgresql'
require_relative 'lib/db_manage/migrate_mssql'
require_relative 'lib/db_manage/migrate_oracle'
require_relative 'lib/db_manage/migrate_job'

Redmine::Plugin.register :db_manage do
  name 'DB 관리'
  author 'kephi-hub'
  description 'DB 서버 접속정보 관리, 프로젝트 DB 스키마 조회·테이블 정의서·개발/운영 비교·용어 점검'
  version '1.13.0'
  url 'https://github.com/kephi-hub/Redmine-KRDS-style'
  requires_redmine version_or_higher: '6.0'

  project_module :db_manage do
    permission :view_db_schema, { db_schemas: [:index, :table, :object, :export, :compare, :check, :erd, :history, :history_diff, :privacy] }, read: true
    permission :manage_db_links, { projects: :settings, db_links: [:new, :create, :edit, :update, :destroy], db_schemas: [:save_history, :query_log, :save_privacy, :codes, :save_codes] }, require: :member
    # SQL 조회: 개발 DB 와 운영 DB 권한을 따로 (운영은 기본으로 아무 역할에도 주지 않음)
    permission :run_db_query, { db_schemas: [:query, :codes] }, require: :member
    permission :run_db_query_production, { db_schemas: [:query, :codes] }, require: :member
    # 이관: 대상이 개발 DB / 운영 DB 인 경우 권한을 따로 (원본은 보기 권한으로 충분)
    permission :migrate_db, { db_migrations: [:index, :preview, :create, :show, :backup] }, require: :member
    permission :migrate_db_production, { db_migrations: [:index, :preview, :create, :show, :backup] }, require: :member
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
# 연결을 지우면 SQL 조회 실행 기록도 함께 지움
DbLink.has_many :db_query_logs, dependent: :delete_all unless DbLink.reflect_on_association(:db_query_logs)
# 연결을 지우면 개인정보 컬럼 표시도 함께 지움
DbLink.has_many :db_privacy_columns, dependent: :delete_all unless DbLink.reflect_on_association(:db_privacy_columns)

# 비밀번호가 로그에 남지 않게
Rails.application.config.filter_parameters += [:password, :ssh_password, :ssh_private_key, :ssh_passphrase]
