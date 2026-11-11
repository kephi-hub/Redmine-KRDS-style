# 역할·권한·업무흐름을 쉽게 보고 설정하는 관리 화면 (Redmine 원본 기능은 그대로, 보기·일괄 설정만 더함)
# - 관리 > 역할 및 권한 > 권한 설정 탭 (1.3.0) : 원본 권한 보고서(권한별 체크·저장)와 권한 한눈에 보기(영역 요약)를 한 화면으로.
#   영역 줄은 관리/작성/보기/없음 요약, 펼치면 실제 권한 체크박스. 이전 주소 /access_overview 는 이 화면으로 이동.
#   (이전 설명) 권한 한눈에 보기 : 역할 × 영역(일감·문서·접속정보·배포 …) 을 관리/작성/보기/없음 으로 요약, 사용자 × 프로젝트 역할표
# - 관리 > 업무흐름 설정 : 역할마다 상태 전환표 하나로 여러 일감 유형에 한 번에 적용 (작성자·담당자 추가 규칙은 그대로)
# - 관리 > 항목 편집 권한 설정 : 역할마다 상태 × 항목 표 하나(편집·읽기 전용·필수)로 여러 일감 유형에 한 번에 적용
# - Redmine 기본 "업무흐름" 메뉴는 관리 메뉴에서 뺌 (화면 자체는 [유형별 상세 편집] 링크로 계속 쓸 수 있음)
require_relative 'lib/access_guide/areas'
require_relative 'lib/access_guide/roles_patch'

Redmine::Plugin.register :access_guide do
  name '역할·업무흐름 안내'
  author 'kephi-hub'
  description '역할별 권한 요약과 업무흐름 간편 설정 (관리자 전용)'
  version '1.3.0'
  url 'https://github.com/kephi-hub/Redmine-KRDS-style'
  requires_redmine version_or_higher: '6.0'
end

# 관리 메뉴는 Redmine 기본 아이콘을 쓰려고 플러그인 밖에서 등록
Redmine::MenuManager.map :admin_menu do |menu|
  menu.delete :workflows
  menu.push :simple_workflows, { controller: 'simple_workflows', action: 'index' },
            caption: :label_simple_workflows, after: :issue_statuses, html: { class: 'icon icon-workflows' }, icon: 'workflows'
  menu.push :field_permissions, { controller: 'field_permissions', action: 'index' },
            caption: :label_field_permissions, after: :simple_workflows, html: { class: 'icon icon-edit' }, icon: 'edit'
end

# 역할 및 권한 > 권한 설정: 원본 RolesController 에 데이터·저장 후 이동만 더함
RolesController.prepend(AccessGuide::RolesPatch) unless RolesController.ancestors.include?(AccessGuide::RolesPatch)
RolesController.helper(AccessOverviewHelper)
