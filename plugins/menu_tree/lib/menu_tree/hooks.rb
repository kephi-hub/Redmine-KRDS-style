# 일감 ↔ 메뉴 연결 — 일감 등록·편집 화면의 "메뉴" 선택칸, 상세 화면의 연결된 메뉴, 저장
module MenuTree
  class Hooks < Redmine::Hook::ViewListener
    render_on :view_issues_form_details_bottom, partial: 'menu_tree_hooks/issue_form'
    render_on :view_issues_show_description_bottom, partial: 'menu_tree_hooks/issue_show'

    def controller_issues_new_after_save(context = {})
      sync(context[:params], context[:issue])
    end

    def controller_issues_edit_after_save(context = {})
      sync(context[:params], context[:issue])
    end

    # 선택칸을 보낸 경우에만 반영 (모듈이 꺼져 있거나 칸이 없던 화면에서는 기존 연결 유지)
    def sync(params, issue)
      return unless params && params[:menu_items_sent] == '1' && issue&.persisted?
      project = issue.project
      return unless MenuTree.enabled_for?(project)
      wanted = Array(params[:menu_item_ids]).map(&:to_i) & MenuItem.where(project_id: project.id).pluck(:id)
      current = MenuItemIssue.where(issue_id: issue.id).pluck(:menu_item_id)
      MenuItemIssue.where(issue_id: issue.id, menu_item_id: current - wanted).delete_all
      (wanted - current).each { |mid| MenuItemIssue.create!(issue_id: issue.id, menu_item_id: mid) }
    end
  end

  def self.enabled_for?(project, user = User.current)
    project&.module_enabled?(:menu_tree) && user.allowed_to?(:view_menu_tree, project)
  end
end
