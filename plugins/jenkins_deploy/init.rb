# Jenkins 배포 연동 — Redmine 프로젝트에서 Jenkins 배포 작업 실행·이력 확인
# 설계: Redmine_Jenkins_배포연동_설계안.md (1단계)
# - 관리 > Jenkins 서버 : 주소·계정·API 토큰(암호화 저장) 등록, 연결 시험 (관리자)
# - 프로젝트 > 설정 > 배포 : 환경(개발·운영 등)별 Jenkins 작업 지정
# - 프로젝트 > 배포 : 배포 실행, 진행 상태, 이력 (Jenkins 기본 원격 API 사용, Jenkins 플러그인 불필요)
require_relative 'lib/jenkins_deploy/client'
require_relative 'lib/jenkins_deploy/project_settings_patch'

Redmine::Plugin.register :jenkins_deploy do
  name 'Jenkins 배포'
  author 'kephi-hub'
  description 'Redmine 프로젝트에서 Jenkins 배포 작업 실행과 이력 확인'
  version '1.0.0'
  url 'https://github.com/kephi-hub/Redmine-KRDS-style'
  requires_redmine version_or_higher: '6.0'

  project_module :jenkins_deploy do
    permission :view_deploys, { deploys: [:index, :status] }, read: true
    permission :run_deploys, { deploys: [:create] }
    permission :run_production_deploys, { deploys: [:create] }
    permission :manage_deploy_targets, { deploy_targets: [:new, :create, :edit, :update, :destroy] }, require: :member
  end

  menu :project_menu, :deploys, { controller: 'deploys', action: 'index' },
       caption: :label_deploy_plural, after: :files, param: :project_id
end

# 관리 메뉴는 Redmine 기본 아이콘을 쓰려고 플러그인 밖에서 등록 (플러그인 등록 메뉴는 플러그인 아이콘 파일을 찾음)
Redmine::MenuManager.map :admin_menu do |menu|
  menu.push :jenkins_servers, { controller: 'jenkins_servers', action: 'index' },
            caption: :label_jenkins_server_plural, after: :plugins,
            html: { class: 'icon icon-server-authentication' }, icon: 'server-authentication'
end

# Redmine 6 은 플러그인 init.rb 를 준비 단계(to_prepare) 이후에 읽으므로 바로 적용 (krds_ui 와 같은 방식)
ProjectsHelper.prepend(JenkinsDeploy::ProjectSettingsPatch) unless ProjectsHelper.ancestors.include?(JenkinsDeploy::ProjectSettingsPatch)
unless Project.reflect_on_association(:deploy_targets)
  # 프로젝트 삭제 시 배포 기록·환경도 함께 삭제
  Project.has_many :deploy_runs, dependent: :delete_all
  Project.has_many :deploy_targets, dependent: :destroy
end

# 토큰이 로그에 남지 않게
Rails.application.config.filter_parameters += [:token]
