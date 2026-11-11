# 프로젝트 메뉴 대분류 — 위쪽은 대분류(개요·일감·설계·개발·운영·산출물·협업), 지금 대분류의 메뉴는 아래 한 줄(.nav_sub)
# - 대분류 링크는 그 안에서 쓸 수 있는 첫 메뉴, 쓸 수 있는 메뉴가 없으면 숨김
# - 합친 메뉴(MERGED): 대표 메뉴가 보이면 위쪽 메뉴에서는 숨기고 화면 안 구역 탭으로 (대표가 없으면 그대로 보임)
# - 목록에 없는 메뉴(새 플러그인)는 "기타"
# - 권한·주소는 Redmine 메뉴 그대로 (menu_items_for 가 권한 확인)
module KrdsUi
  module MenuGroups
    GROUPS = [
      [:overview, %i(overview activity)],
      [:work, %i(issues new_issue gantt calendar roadmap time_entries)],
      [:design, %i(qa_requirements menu_items glossary)],
      [:dev, %i(repository programs db_schemas qa_tests deploys)],
      [:ops, %i(ops_assets ops_schedules ops_incidents ops_interfaces keys)],
      [:docs, %i(deliverables meetings risks documents files)],
      [:collab, %i(wiki boards news)]
    ].freeze
    MERGED = { sys_roles: :menu_items, change_requests: :qa_requirements }.freeze
    FIXED = %i(new_object settings).freeze
  end

  module MenuHelperPatch
    def render_main_menu(project)
      return super unless project && !project.new_record? && controller.current_menu(project) == :project_menu
      krds_grouped_menu(project) || super
    end

    private

    def krds_grouped_menu(project)
      nodes = []
      menu_items_for(:project_menu, project) { |n| nodes << n }
      return nil if nodes.empty?
      by = nodes.index_by(&:name)
      merged = KrdsUi::MenuGroups::MERGED
      hidden = merged.select { |child, parent| by[child] && by[parent] }.keys
      current = current_menu_item
      current = merged[current] if hidden.include?(current)
      known = KrdsUi::MenuGroups::GROUPS.flat_map(&:last) + merged.keys + KrdsUi::MenuGroups::FIXED
      groups = KrdsUi::MenuGroups::GROUPS.map do |key, names|
        list = names.flat_map { |n| [n] + merged.select { |c, p| p == n && !hidden.include?(c) }.keys }
        [key, list.filter_map { |n| by[n] }]
      end
      etc = nodes.reject { |n| known.include?(n.name) }
      groups << [:etc, etc]
      groups.reject! { |_, list| list.empty? }
      sub = nil
      lis = []
      lis << render_menu_node(by[:new_object], project) if by[:new_object]
      groups.each do |key, list|
        entries = list.map { |n| caption, url, _ = extract_node_details(n, project); [n, caption, url, n.name == current] }
        active = entries.any?(&:last)
        label = l("label_nav_#{key}")
        first = entries.first
        if entries.size == 1
          lis << content_tag(:li, link_to(label, first[2], class: "nav_grp #{'selected' if active}".strip, title: first[1]))
        else
          items = safe_join(entries.map { |n, caption, url, sel| content_tag(:li, render_single_menu_node(n, caption, url, sel)) })
          lis << content_tag(:li, link_to(label, first[2], class: "nav_grp #{'selected' if active}".strip) + content_tag(:ul, items, class: 'menu-children'), class: 'nav_parent')
          sub = items if active
        end
      end
      if (s = by[:settings])
        caption, url, sel = extract_node_details(s, project)
        lis << content_tag(:li, render_single_menu_node(s, caption, url, sel))
      end
      html = content_tag(:ul, safe_join(lis))
      html += content_tag(:div, content_tag(:ul, sub), class: 'nav_sub') if sub
      html
    end
  end

  # 합친 메뉴의 화면 위 구역 탭 — items: [[이름, 주소, 지금 화면?], …] (보일 것만), 2개 이상일 때만
  module SectionTabsHelper
    def krds_section_tabs(items)
      items = items.compact
      return ''.html_safe if items.size < 2
      content_tag(:nav, safe_join(items.map { |label, url, on| link_to(label, url, class: (on ? 'on' : nil), 'aria-current': (on ? 'page' : nil)) }),
                  class: 'nav_sec', 'aria-label': l(:label_nav_section))
    end
  end
end
