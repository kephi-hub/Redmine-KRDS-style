# 저장소 폴더 화면 위쪽에 [소스코드 다운로드] 버튼 (지금 보고 있는 폴더·리비전 기준)
module SiteTools
  class Hooks < Redmine::Hook::ViewListener
    def view_repositories_show_contextual(context = {})
      controller = context[:controller]
      repo = context[:repository]
      project = context[:project]
      return '' unless controller && controller.action_name == 'show' && repo && SiteTools::RepoExport.supported?(repo)
      return '' unless User.current.allowed_to?(:export_repository, project)
      path = controller.params[:path].is_a?(Array) ? controller.params[:path].join('/') : controller.params[:path].to_s
      rev = controller.params[:rev].presence
      where = path.present? ? "/#{path}" : I18n.t(:label_repo_export_root)
      url = controller.url_for(controller: 'repo_exports', action: 'show', project_id: project.identifier, repository_id: repo.identifier_param, path: path.presence, rev: rev, only_path: true)
      title = I18n.t(:text_repo_export_title, where: where, rev: rev || 'HEAD')
      link = controller.view_context.link_to(controller.view_context.sprite_icon('download', I18n.t(:label_repo_export)), url, class: 'icon icon-download st_export', title: title,
                                             data: { confirm: I18n.t(:text_repo_export_confirm, where: where, rev: rev || 'HEAD') })
      controller.view_context.content_tag(:div, link, class: 'contextual')
    end
  end
end
