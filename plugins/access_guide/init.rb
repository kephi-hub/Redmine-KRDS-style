# 역할·권한·업무흐름을 쉽게 보고 설정하는 관리 화면 (Redmine 원본 기능은 그대로, 보기·일괄 설정만 더함)
# - 관리 > 권한 한눈에 보기 : 역할 × 영역(일감·문서·접속정보·배포 …) 을 관리/작성/보기/없음 으로 요약, 사용자 × 프로젝트 역할표
# - 관리 > 업무흐름 간편 설정 : 역할마다 상태 전환표 하나로 여러 일감 유형에 한 번에 적용 (작성자·담당자 추가 규칙, 필드 권한은 그대로)
require_relative 'lib/access_guide/areas'

Redmine::Plugin.register :access_guide do
  name '역할·업무흐름 안내'
  author 'kephi-hub'
  description '역할별 권한 요약과 업무흐름 간편 설정 (관리자 전용)'
  version '1.0.0'
  url 'https://github.com/kephi-hub/Redmine-KRDS-style'
  requires_redmine version_or_higher: '6.0'
end

# 관리 메뉴는 Redmine 기본 아이콘을 쓰려고 플러그인 밖에서 등록
Redmine::MenuManager.map :admin_menu do |menu|
  menu.push :access_overview, { controller: 'access_overview', action: 'index' },
            caption: :label_access_overview, after: :roles, html: { class: 'icon icon-roles' }, icon: 'roles'
  menu.push :simple_workflows, { controller: 'simple_workflows', action: 'index' },
            caption: :label_simple_workflows, after: :workflows, html: { class: 'icon icon-workflows' }, icon: 'workflows'
end
