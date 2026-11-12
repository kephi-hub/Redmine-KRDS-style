# 프로젝트 개요 위 종합 대시보드 (화면 스크립트가 개요 맨 위로 옮김)
module PmKit
  class Hooks < Redmine::Hook::ViewListener
    render_on :view_projects_show_left, partial: 'pm_docs/dashboard'
  end
end
