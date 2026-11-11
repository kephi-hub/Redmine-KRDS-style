module GlossaryHelper
  # 이 화면에서 용어를 고칠 수 있는지: 공통은 관리자, 프로젝트 용어는 그 프로젝트 관리 권한
  def glossary_editable?(term)
    return User.current.admin? if term.common?
    @project && term.project_id == @project.id && User.current.allowed_to?(:manage_glossary, @project)
  end

  def glossary_can_manage?
    @project ? User.current.allowed_to?(:manage_glossary, @project) : User.current.admin?
  end

  def glossary_path_for(action, term = nil, options = {})
    if @project
      case action
      when :new then new_project_glossary_term_path(@project, options)
      when :edit then edit_project_glossary_term_path(@project, term, options)
      when :member then project_glossary_term_path(@project, term, options)
      when :export then export_project_glossary_terms_path(@project, options)
      when :import then import_project_glossary_terms_path(@project, options)
      else project_glossary_terms_path(@project, options)
      end
    else
      case action
      when :new then new_glossary_term_path(options)
      when :edit then edit_glossary_term_path(term, options)
      when :member then glossary_term_path(term, options)
      when :export then export_glossary_terms_path(options)
      when :import then import_glossary_terms_path(options)
      else glossary_terms_path(options)
      end
    end
  end
end
