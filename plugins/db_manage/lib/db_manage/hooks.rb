# 위키·일감·문서 본문의 ```mermaid 블록을 그림으로 (블록이 있을 때만 Mermaid 를 불러옴, 인터넷 연결 불필요)
module DbManage
  class Hooks < Redmine::Hook::ViewListener
    def view_layouts_base_html_head(context = {})
      src = context[:controller].view_context.javascript_path('plugin_assets/db_manage/mermaid.min')
      loader = context[:controller].view_context.javascript_path('plugin_assets/db_manage/mermaid_loader')
      %(<script>window.DB_MERMAID_SRC = #{src.to_json};</script>\n<script src="#{ERB::Util.h(loader)}" defer></script>).html_safe
    end
  end
end
