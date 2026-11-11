# 일감 상세: 연결된 요구사항, 테스트 결함이면 어느 회차·케이스에서 나왔는지
module QaTrace
  class Hooks < Redmine::Hook::ViewListener
    render_on :view_issues_show_description_bottom, partial: 'qa_trace_hooks/issue_show'
  end

  def self.requirements_on?(project, user = User.current)
    project&.module_enabled?(:qa_requirements) && user.allowed_to?(:view_qa_requirements, project)
  end

  def self.tests_on?(project, user = User.current)
    project&.module_enabled?(:qa_tests) && user.allowed_to?(:view_qa_tests, project)
  end
end
