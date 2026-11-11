# 저장소 화면 위쪽: "저장소" 제목 + 오른쪽 버튼 줄(Redmine 원본 통계·더보기·개정판 + [소스코드 다운로드])
# theme.js 가 원본 #content > .contextual 을 .repo_btns 로 옮김. 다운로드 버튼은 폴더 화면(show)에서 지금 폴더·리비전 기준
module SiteTools
  class Hooks < Redmine::Hook::ViewListener
    def view_repositories_show_contextual(context = {})
      controller = context[:controller]
      repo = context[:repository]
      project = context[:project]
      return '' unless controller && repo
      v = controller.view_context
      btn = ''.html_safe
      if controller.action_name == 'show' && SiteTools::RepoExport.supported?(repo) && User.current.allowed_to?(:export_repository, project)
        path = controller.params[:path].is_a?(Array) ? controller.params[:path].join('/') : controller.params[:path].to_s
        rev = controller.params[:rev].presence
        where = path.present? ? "/#{path}" : I18n.t(:label_repo_export_root)
        url = controller.url_for(controller: 'repo_exports', action: 'show', project_id: project.identifier, repository_id: repo.identifier_param, path: path.presence, rev: rev, only_path: true)
        btn = v.link_to(v.sprite_icon('download', I18n.t(:label_repo_export)), url, class: 'icon icon-download st_export',
                        title: I18n.t(:text_repo_export_title, where: where, rev: rev || 'HEAD'),
                        data: { confirm: I18n.t(:text_repo_export_confirm, where: where, rev: rev || 'HEAD') })
      end
      title = I18n.t(:label_repository) + (project.repositories.size > 1 && repo.identifier.present? ? " · #{repo.identifier}" : '')
      v.content_tag(:div, v.content_tag(:h2, title, class: 'repo_tit') + v.content_tag(:div, btn, class: 'repo_btns'), class: 'repo_bar')
    end
  end
end
