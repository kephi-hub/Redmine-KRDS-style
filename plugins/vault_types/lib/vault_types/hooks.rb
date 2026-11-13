# 프로젝트 접속정보 목록 — 드래그 정렬 스크립트 (편집 권한 + 제목 칸 정렬을 쓰지 않을 때)
module VaultTypes
  class Hooks < Redmine::Hook::ViewListener
    def view_layouts_base_html_head(context = {})
      c = context[:controller]
      return '' unless c.is_a?(KeysController) && c.action_name == 'index'
      project = c.instance_variable_get(:@project)
      return '' unless project && c.params[:sort].blank? && User.current.allowed_to?(:edit_keys, project)
      cfg = { url: project_keys_order_path(project), saved: I18n.t(:notice_vk_order_saved), failed: I18n.t(:error_vk_order),
              moved: I18n.t(:text_vk_order_moved) }
      javascript_tag("window.VK_ORDER = #{cfg.to_json};") + javascript_include_tag('key_order', plugin: 'vault_types')
    end
  end
end
