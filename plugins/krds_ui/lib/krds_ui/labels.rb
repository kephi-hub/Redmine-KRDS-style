# 화면에 보이는 이름만 바꾸기 — 메뉴(상단·프로젝트)의 표시 이름, 프로젝트 대분류, 모듈 설정 화면의 모듈 이름
# 번역 문구는 그대로 두므로 페이지 제목·다른 화면 문구는 바뀌지 않음
# 요청마다 한 번 읽음(Current) — 저장하면 다음 요청부터 모든 프로세스에 반영
module KrdsUi
  module Labels
    class Current < ActiveSupport::CurrentAttributes
      attribute :map
    end

    # 관리 화면에 보여 줄 메뉴 (관리 메뉴는 제외)
    TOP_MENUS = %i(top_menu account_menu application_menu).freeze
    SKIP = %i(new_object).freeze

    module_function

    def map
      Current.map ||= begin
        KrdsLabel.pluck(:kind, :key, :name).each_with_object({}) { |(k, key, n), h| h["#{k}:#{key}"] = n }
      rescue StandardError
        {}
      end
    end

    def get(kind, key)
      map["#{kind}:#{key}"].presence
    end

    def nodes(menu)
      out = []
      walk = ->(n) { n.children.each { |c| out << c; walk.(c) } }
      walk.(Redmine::MenuManager.items(menu))
      out
    end

    # 메뉴 항목 → kind (top/project), 관리 메뉴 등은 nil
    def kind_of(item)
      @kinds ||= begin
        h = {}
        TOP_MENUS.each { |m| nodes(m).each { |n| h[n.object_id] = 'top' } }
        nodes(:project_menu).each { |n| h[n.object_id] = 'project' }
        h
      end
      @kinds[item.object_id]
    end

    def menu_name(item)
      kind = kind_of(item) or return nil
      get(kind, item.name)
    end

    def group(key)
      get('group', key) || I18n.t("label_nav_#{key}")
    end

    def module_name(name)
      get('module', name) || I18n.t("project_module_#{name}", default: name.to_s.humanize)
    end

    # 관리 화면 목록 — [[kind, 제목, [[key, 기본 이름], ...]], ...]
    def catalog
      top = TOP_MENUS.flat_map { |m| nodes(m) }.uniq(&:name).reject { |n| SKIP.include?(n.name) }
      project = nodes(:project_menu).uniq(&:name).reject { |n| SKIP.include?(n.name) }
      groups = KrdsUi::MenuGroups::GROUPS.map(&:first) + [:etc]
      [
        ['top', I18n.t(:label_krds_lb_top), top.map { |n| [n.name.to_s, default_caption(n)] }],
        ['group', I18n.t(:label_krds_lb_group), groups.map { |k| [k.to_s, I18n.t("label_nav_#{k}")] }],
        ['project', I18n.t(:label_krds_lb_project), project.map { |n| [n.name.to_s, default_caption(n)] }],
        ['module', I18n.t(:label_krds_lb_module), Redmine::AccessControl.available_project_modules.map { |m| [m.to_s, I18n.t("project_module_#{m}", default: m.to_s.humanize)] }]
      ]
    end

    def default_caption(node)
      node.krds_default_caption.to_s
    rescue StandardError
      node.name.to_s.humanize
    end

    # Redmine 메뉴 항목 표시 이름에 적용
    module CaptionPatch
      def caption(project = nil)
        KrdsUi::Labels.menu_name(self) || super
      end

      def krds_default_caption(project = nil)
        method(:caption).super_method.call(project)
      end
    end
  end
end
