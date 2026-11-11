# 용어사전 — 프로젝트 용어사전 + 전사 공통 용어사전(관리 메뉴), CSV 가져오기·내보내기, 위키 매크로 {{term(용어)}}
# DB 관리 플러그인의 "용어 점검" 이 이 사전의 약어(컬럼명)를 기준으로 씀
Redmine::Plugin.register :glossary do
  name '용어사전'
  author 'kephi-hub'
  description '프로젝트·전사 공통 용어사전 (용어·영문명·약어·데이터 타입·정의), CSV 가져오기·내보내기, 위키 매크로'
  version '1.0.0'
  url 'https://github.com/kephi-hub/Redmine-KRDS-style'
  requires_redmine version_or_higher: '6.0'

  project_module :glossary do
    permission :view_glossary, { glossary_terms: [:index, :export] }, read: true
    permission :manage_glossary, { glossary_terms: [:new, :create, :edit, :update, :destroy, :import] }, require: :member
  end

  menu :project_menu, :glossary, { controller: 'glossary_terms', action: 'index' },
       caption: :label_glossary, after: :documents, param: :project_id
end

# 관리 메뉴 (Redmine 기본 아이콘 사용)
Redmine::MenuManager.map :admin_menu do |menu|
  menu.push :glossary_common, { controller: 'glossary_terms', action: 'index' },
            caption: :label_glossary_common, after: :enumerations, html: { class: 'icon icon-list' }, icon: 'list'
end

# 위키·일감 본문에서 {{term(고객번호)}} → 용어 표시 + 약어 + 정의 툴팁 (볼 권한이 있을 때)
Redmine::WikiFormatting::Macros.register do
  desc "용어사전 용어를 표시합니다. 예: {{term(고객번호)}}"
  macro :term do |obj, args|
    name = args.first.to_s.strip
    raise '용어를 적어 주세요. 예: {{term(고객번호)}}' if name.blank?
    project = @project || (obj.respond_to?(:project) ? obj.project : nil)
    term = project && User.current.allowed_to?(:view_glossary, project) ? GlossaryTerm.lookup(project, name) : nil
    if term
      label = term.abbr.present? ? "#{term.name} (#{term.abbr})" : term.name
      link_to(label, project_glossary_terms_path(project, q: term.name), class: 'gl_term', title: term.definition.to_s.truncate(300))
    else
      content_tag(:span, name, class: 'gl_term gl_missing', title: l(:label_glossary_missing))
    end
  end
end
