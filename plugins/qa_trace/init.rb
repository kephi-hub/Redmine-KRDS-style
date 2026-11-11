# 요구사항 추적 · 테스트
# - 프로젝트 > 요구사항 : 공공 표준 분류(SFR·PER…) ID, 메뉴·일감 연결, 추적표(요구사항 → 메뉴 → 일감 → 테스트), 위험 표시, 변경 이력,
#   요구사항 정의서·추적표 엑셀 가져오기·내보내기
# - 프로젝트 > 테스트 : 케이스(메뉴·요구사항 연결), 회차별 결과 입력, 불합격 → 결함 일감, 재테스트 표시, 메뉴별 현황,
#   테스트 시나리오·결과서 엑셀
# 메뉴는 menu_tree 플러그인, 엑셀 쓰기·읽기는 krds_ui 플러그인 공통 기능 사용
require_relative 'lib/qa_trace/trace'
require_relative 'lib/qa_trace/sheet'
require_relative 'lib/qa_trace/hooks'

Redmine::Plugin.register :qa_trace do
  name '요구사항 · 테스트'
  author 'kephi-hub'
  description '요구사항 추적표(메뉴·일감·테스트 연결)와 테스트 케이스·회차·결함 관리'
  version '1.0.0'
  url 'https://github.com/kephi-hub/Redmine-KRDS-style'
  requires_redmine version_or_higher: '6.0'

  project_module :qa_requirements do
    permission :view_qa_requirements, { qa_requirements: [:index, :trace, :show, :export] }, read: true
    permission :manage_qa_requirements, { qa_requirements: [:new, :create, :edit, :update, :destroy, :import] }, require: :member
  end
  project_module :qa_tests do
    permission :view_qa_tests, { qa_test_cases: [:index, :menus, :show, :export], qa_test_runs: [:index, :show, :export] }, read: true
    permission :run_qa_tests, { qa_test_runs: [:save, :defect] }, require: :member
    permission :manage_qa_tests, { qa_test_cases: [:new, :create, :edit, :update, :destroy, :import],
                                   qa_test_runs: [:new, :create, :edit, :update, :destroy, :sync] }, require: :member
  end

  menu :project_menu, :qa_requirements, { controller: 'qa_requirements', action: 'index' },
       caption: :label_qa_requirements, after: :sys_roles, param: :project_id
  menu :project_menu, :qa_tests, { controller: 'qa_test_cases', action: 'index' },
       caption: :label_qa_tests, after: :qa_requirements, param: :project_id
end

# Redmine 6 은 init.rb 를 준비 단계 이후에 읽으므로 바로 적용
unless Project.reflect_on_association(:qa_requirements)
  # 프로젝트 삭제 시 요구사항·케이스·회차와 그 연결·결과·이력도 함께
  Project.has_many :qa_requirements, dependent: :destroy
  Project.has_many :qa_test_cases, dependent: :destroy
  Project.has_many :qa_test_runs, dependent: :destroy
end
# 일감을 지우면 요구사항 연결이 풀리고, 결함으로 연결된 테스트 결과는 일감 번호만 비움
Issue.has_many :qa_requirement_issues, dependent: :delete_all unless Issue.reflect_on_association(:qa_requirement_issues)
Issue.has_many :qa_test_results, dependent: :nullify unless Issue.reflect_on_association(:qa_test_results)
# 메뉴를 지우면 요구사항 연결이 풀리고 케이스의 메뉴는 비움
if Redmine::Plugin.installed?(:menu_tree)
  MenuItem.has_many :qa_requirement_menus, dependent: :delete_all unless MenuItem.reflect_on_association(:qa_requirement_menus)
  MenuItem.has_many :qa_test_cases, dependent: :nullify unless MenuItem.reflect_on_association(:qa_test_cases)
end
# 일감 상세의 연결 표시(배지)에 쓰는 도우미
IssuesController.helper(QaTraceHelper)
