# 메뉴 구조도 · 시스템 권한
# - 프로젝트 > 메뉴 구조도 : 엑셀형 표(뎁스 칸 자동, 칸 바로 편집, Tab 들여쓰기), 추가 칼럼, 일감 연결(메뉴 하나에 여러 일감),
#   메뉴별 일감 일괄 생성, 엑셀 가져오기·내보내기, 구조도(Mermaid) 그림, 현황(1뎁스별 진행률)
# - 프로젝트 > 시스템 권한 : 개발 대상 시스템의 사용자 권한 등급, 메뉴 × 권한 매트릭스(조회/편집/전체), 엑셀 내보내기
# - 일감 : 등록·편집 화면에 메뉴 선택(여러 개), 상세에 연결된 메뉴, 일감 목록에 "메뉴" 열·검색조건(하위 메뉴 포함)
# 그림(Mermaid)·엑셀 쓰기·읽기는 krds_ui 플러그인 공통 기능 사용
require_relative 'lib/menu_tree/current'
require_relative 'lib/menu_tree/site_scope'
require_relative 'lib/menu_tree/sheet'
require_relative 'lib/menu_tree/stats'
require_relative 'lib/menu_tree/hooks'
require_relative 'lib/menu_tree/issue_query_patch'

Redmine::Plugin.register :menu_tree do
  name '메뉴 구조도'
  author 'kephi-hub'
  description '메뉴 구조도(사이트별 · 엑셀형 편집·일감 연결·구조도·현황)와 시스템 권한 매트릭스'
  version '1.1.0'
  url 'https://github.com/kephi-hub/Redmine-KRDS-style'
  requires_redmine version_or_higher: '6.0'

  project_module :menu_tree do
    permission :view_menu_tree, { menu_items: [:index, :data, :diagram, :status, :export] }, read: true
    permission :manage_menu_tree, { menu_items: [:create, :update, :move, :destroy, :import, :issues],
                                    menu_columns: [:create, :update, :destroy], menu_sites: [:create, :update, :destroy] }, require: :member
  end
  project_module :sys_roles do
    permission :view_sys_roles, { sys_roles: [:index, :matrix, :export] }, read: true
    permission :manage_sys_roles, { sys_roles: [:new, :create, :edit, :update, :destroy, :save_matrix] }, require: :member
  end

  menu :project_menu, :menu_items, { controller: 'menu_items', action: 'index' },
       caption: :label_menu_tree, after: :glossary, param: :project_id
  menu :project_menu, :sys_roles, { controller: 'sys_roles', action: 'index' },
       caption: :label_sys_roles, after: :menu_items, param: :project_id
end

# Redmine 6 은 init.rb 를 준비 단계 이후에 읽으므로 바로 적용
unless Issue.reflect_on_association(:menu_item_issues)
  Issue.has_many :menu_item_issues, dependent: :delete_all
  Issue.has_many :menu_items, -> { order(:position, :id) }, through: :menu_item_issues
end
unless Project.reflect_on_association(:menu_roots)
  # 프로젝트 삭제 시: 최상위 메뉴를 지우면 하위 메뉴·일감 연결·권한도 함께 지워짐
  Project.has_many :menu_roots, -> { where(parent_id: nil) }, class_name: 'MenuItem', dependent: :destroy
  Project.has_many :menu_columns, dependent: :delete_all
  Project.has_many :menu_sites, dependent: :delete_all
  Project.has_many :sys_roles, dependent: :destroy
end
IssueQuery.prepend(MenuTree::IssueQueryPatch) unless IssueQuery.ancestors.include?(MenuTree::IssueQueryPatch)
