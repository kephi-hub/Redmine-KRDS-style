# 프로젝트 > 설정 에 "DB" 탭 추가 (DB 관리 모듈이 켜져 있고 DB 연결 관리 권한이 있을 때)
module DbManage
  module ProjectSettingsPatch
    def project_settings_tabs
      tabs = super
      if @project.module_enabled?(:db_manage) && User.current.allowed_to?(:manage_db_links, @project)
        tabs << { name: 'db_links', action: :manage_db_links, partial: 'db_links/settings', label: :label_db_manage }
      end
      tabs
    end
  end
end
