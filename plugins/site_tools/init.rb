# 관리 도구
# - 관리 > 메일 서버(SMTP): 화면에서 SMTP 설정(비밀번호 암호화 저장), 저장 전 시험 메일, 저장하면 바로 적용(재시작 불필요)
#   config/configuration.yml 에 email_delivery 가 있으면 그쪽이 우선
# - 관리 > 저장소 사용자 연결: 저장소 커미터를 지금 사용자 로그인 ID·메일 기준으로 자동 연결(미연결만, 선택 시 다시 맞추기),
#   저장소 "사용자" 화면에 [자동 연결] 버튼, 사용자를 만들거나 로그인 ID 를 바꾸면 같은 ID 의 미연결 커미터를 자동 연결,
#   rake redmine:site_tools:map_committers
# - 관리 > 백업: PMS 백업(서버 setup/backup.sh — DB·첨부·Vault 키, 날짜별 스냅숏) 목록·상태·[지금 백업]
# - 관리 > 외부 접속 허용 IP: 외부 프록시(250 nginx)를 거친 접속만 IP 목록으로 제한, 사내 직접 접속은 제한 없음
# - 저장소 > [소스코드 다운로드]: 지금 폴더·리비전을 zip 으로 (SVN svn export · Git git archive), 권한 "소스코드 다운로드", 받은 기록
require_relative 'lib/site_tools/smtp'
require_relative 'lib/site_tools/committers'
require_relative 'lib/site_tools/user_patch'
require_relative 'lib/site_tools/repo_export'
require_relative 'lib/site_tools/hooks'
require_relative 'lib/site_tools/backup'
require_relative 'lib/site_tools/ext_access'

Redmine::Plugin.register :site_tools do
  name '관리 도구'
  author 'kephi-hub'
  description '메일 서버(SMTP) 설정 화면, 저장소 커미터 ↔ 사용자 자동 연결, 소스코드 다운로드, PMS 백업 현황, 외부 접속 허용 IP'
  version '1.3.0'
  url 'https://github.com/kephi-hub/Redmine-KRDS-style'
  requires_redmine version_or_higher: '6.0'
  settings default: SiteTools::Smtp::DEFAULTS.dup

  # 저장소 모듈에 권한 추가 (전체 소스를 받으므로 저장소 보기와 따로)
  permission :export_repository, { repo_exports: [:show] }, project_module: :repository, require: :member
end

Redmine::MenuManager.map :admin_menu do |menu|
  menu.push :smtp_settings, { controller: 'smtp_settings', action: 'index' },
            caption: :label_smtp_settings, after: :settings, html: { class: 'icon icon-email' }, icon: 'email'
  menu.push :committer_maps, { controller: 'committer_maps', action: 'index' },
            caption: :label_committer_maps, after: :smtp_settings, html: { class: 'icon icon-changeset' }, icon: 'changeset'
  menu.push :pms_backups, { controller: 'pms_backups', action: 'index' },
            caption: :label_pms_backups, after: :committer_maps, html: { class: 'icon icon-save' }, icon: 'save'
  menu.push :ext_access, { controller: 'ext_access', action: 'index' },
            caption: :label_ext_access, after: :pms_backups, html: { class: 'icon icon-lock' }, icon: 'lock'
end

User.prepend(SiteTools::UserPatch) unless User.ancestors.include?(SiteTools::UserPatch)
# 외부 접속 허용 IP — 모든 화면·API 의 user_setup 뒤(로그인 검사 전)에 확인 (메서드 덮어쓰기라 이미 읽힌 하위 컨트롤러에도 적용)
ApplicationController.prepend(SiteTools::ExtAccess::Guard) unless ApplicationController.ancestors.include?(SiteTools::ExtAccess::Guard)
# 시작할 때 저장된 SMTP 설정 적용 (DB 준비 전이면 건너뜀)
begin
  SiteTools::Smtp.apply! if ActiveRecord::Base.connection.table_exists?(:settings)
rescue StandardError
  nil
end
