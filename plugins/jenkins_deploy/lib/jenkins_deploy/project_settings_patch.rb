# 프로젝트 > 설정 에 "배포" 탭 추가 (배포 모듈이 켜져 있고 배포 설정 관리 권한이 있을 때)
module JenkinsDeploy
  module ProjectSettingsPatch
    def project_settings_tabs
      tabs = super
      if @project.module_enabled?(:jenkins_deploy) && User.current.allowed_to?(:manage_deploy_targets, @project)
        tabs << { name: 'deploys', action: :manage_deploy_targets, partial: 'deploy_targets/settings', label: :label_deploy_plural }
      end
      tabs
    end
  end
end
