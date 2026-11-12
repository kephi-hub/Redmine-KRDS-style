# 메인 메뉴 — KRDS 메인 메뉴(2뎁스) 형태 (https://www.krds.go.kr/html/site/component/component_03_02.html)
# - PC: 1뎁스는 하위 메뉴가 있으면 버튼(꺾쇠·열림 막대), 없으면 링크. 누르면(마우스오버 아님) 머리글 아래 전체 너비 2뎁스 패널 + 화면 어둡게
#   (theme.js 가 패널을 머리글 아래로 옮기고 열기·닫기·Esc 처리)
# - 모바일: 오른쪽 메뉴 레이어 안에 왼쪽 1뎁스 세로 탭 + 오른쪽 2뎁스 묶음(이어서 스크롤, 스크롤 위치에 따라 탭 표시) — .mnav
# - 프로젝트 메뉴: 대분류(개요·일감·설계·개발·운영·산출물·협업) 아래 2뎁스, 목록에 없는 메뉴(새 플러그인)는 "기타"
# - 초기화면 등 프로젝트 밖 메뉴(application_menu): 1뎁스 링크만
# - 권한·주소는 Redmine 메뉴 그대로 (menu_items_for 가 권한 확인)
module KrdsUi
  module MenuGroups
    GROUPS = [
      [:overview, %i(overview activity)],
      [:work, %i(issues new_issue gantt calendar roadmap time_entries)],
      [:design, %i(qa_requirements change_requests menu_items sys_roles glossary)],
      [:dev, %i(repository programs db_schemas qa_tests sec_scans deploys)],
      [:ops, %i(ops_assets ops_schedules ops_incidents ops_interfaces keys)],
      [:docs, %i(deliverables pm_reports meetings risks audits staff documents files)],
      [:collab, %i(wiki boards news)]
    ].freeze
    FIXED = %i(new_object settings).freeze
    # 2뎁스 메뉴 아이콘 (Redmine 6 기본 아이콘 세트 config/icon_source.yml 의 이름), 없는 메뉴는 FALLBACK
    ICONS = {
      overview: 'project', activity: 'history',
      issues: 'issue', new_issue: 'add', gantt: 'stats', calendar: 'calendar', roadmap: 'package', time_entries: 'time',
      qa_requirements: 'checked', change_requests: 'issue-edit', menu_items: 'list', sys_roles: 'roles', glossary: 'bulb',
      repository: 'changeset', programs: 'apps', db_schemas: 'table-multiple', qa_tests: 'shield-check', deploys: 'arrow-narrow-right',
      ops_assets: 'server-authentication', ops_schedules: 'hourglass', ops_incidents: 'alert-circle', ops_interfaces: 'link', keys: 'key',
      deliverables: 'folder-open', meetings: 'comments', risks: 'warning', documents: 'document', files: 'file',
      pm_reports: 'summary', audits: 'message-report', staff: 'group', sec_scans: 'lock',
      wiki: 'wiki-page', boards: 'message', news: 'news', settings: 'settings'
    }.freeze
    FALLBACK_ICON = 'arrow-right'
    # Redmine 기본 아이콘 세트에 없는 아이콘 — Tabler Icons(MIT) 선 아이콘을 그대로 (stroke 는 CSS)
    INLINE_ICONS = {
      'calendar' => '<svg class="s18 icon-svg" viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' \
                    '<path d="M4 7a2 2 0 0 1 2 -2h12a2 2 0 0 1 2 2v12a2 2 0 0 1 -2 2h-12a2 2 0 0 1 -2 -2v-12z"/><path d="M16 3v4"/><path d="M8 3v4"/>' \
                    '<path d="M4 11h16"/><path d="M11 15h1"/><path d="M12 15v3"/></svg>'
    }.freeze
    # 프로젝트 모듈 선택 화면의 대분류 (메뉴와 같은 묶음, 목록에 없는 모듈은 "기타")
    MODULE_GROUPS = [
      [:work, %w(issue_tracking time_tracking gantt calendar)],
      [:design, %w(qa_requirements change_requests menu_tree sys_roles glossary)],
      [:dev, %w(repository programs db_manage qa_tests sec_scans jenkins_deploy)],
      [:ops, %w(ops_assets ops_schedules ops_logs ops_interfaces keys)],
      [:docs, %w(deliverables pm_reports meetings risks audits staff documents files)],
      [:collab, %w(wiki boards news)]
    ].freeze
  end

  module MenuHelperPatch
    def render_main_menu(project)
      menu = controller.current_menu(project)
      return super unless menu
      return (krds_grouped_menu(project) || super) if menu == :project_menu && project && !project.new_record?
      krds_flat_menu(menu, project) || super
    end

    private

    def krds_entries(nodes, project, current)
      nodes.map do |n|
        caption, url, _ = extract_node_details(n, project)
        [n, caption, url, n.name == current]
      end
    end

    def krds_link(caption, url, sel, css, name = nil)
      icon = KrdsUi::MenuGroups::ICONS[name] || KrdsUi::MenuGroups::FALLBACK_ICON
      svg = KrdsUi::MenuGroups::INLINE_ICONS[icon]&.html_safe || sprite_icon(icon)
      body = name ? safe_join([content_tag(:span, svg, class: 'gnb_ico', 'aria-hidden': 'true'),
                               content_tag(:span, caption)]) : caption
      link_to(body, url, class: [css, (sel ? 'on' : nil)].compact.join(' '), 'aria-current': (sel ? 'page' : nil))
    end

    # 프로젝트 밖 메뉴: 1뎁스 링크만 (모바일 레이어에서는 목록)
    def krds_flat_menu(menu, project)
      nodes = []
      menu_items_for(menu, project) { |n| nodes << n }
      return nil if nodes.empty?
      lis = krds_entries(nodes, project, current_menu_item).map do |n, caption, url, sel|
        content_tag(:li, link_to(caption, url, class: "gnb_trigger is_link #{n.name}#{' selected' if sel}", 'aria-current': (sel ? 'page' : nil)))
      end
      content_tag(:ul, safe_join(lis), class: 'gnb_menu')
    end

    def krds_grouped_menu(project)
      nodes = []
      menu_items_for(:project_menu, project) { |n| nodes << n }
      return nil if nodes.empty?
      by = nodes.index_by(&:name)
      current = current_menu_item
      known = KrdsUi::MenuGroups::GROUPS.flat_map(&:last) + KrdsUi::MenuGroups::FIXED
      groups = KrdsUi::MenuGroups::GROUPS.map { |key, names| [key, names.filter_map { |n| by[n] }] }
      groups << [:etc, nodes.reject { |n| known.include?(n.name) }]
      groups.reject! { |_, list| list.empty? }
      lis = []
      mtabs = []
      msecs = []
      lis << render_menu_node(by[:new_object], project) if by[:new_object]
      groups.each do |key, list|
        entries = krds_entries(list, project, current)
        active = entries.any?(&:last)
        label = l("label_nav_#{key}")
        pid = "gnb_p_#{key}"
        mid = "mnav_#{key}"
        links = safe_join(entries.map { |n, caption, url, sel| content_tag(:li, krds_link(caption, url, sel, 'gnb_link', n.name)) })
        if entries.size == 1
          _, caption, url, sel = entries.first
          lis << content_tag(:li, link_to(label, url, class: "gnb_trigger is_link#{' selected' if active}", title: caption, 'aria-current': (sel ? 'page' : nil)))
        else
          trigger = content_tag(:button, label, type: 'button', class: "gnb_trigger#{' selected' if active}", 'aria-expanded': 'false', 'aria-controls': pid)
          panel = content_tag(:div, content_tag(:div, content_tag(:h2, label, class: 'gnb_tit') + content_tag(:ul, links, class: 'gnb_list'), class: 'gnb_inner'),
                              id: pid, class: 'gnb_panel', hidden: true)
          lis << content_tag(:li, trigger + panel)
        end
        mtabs << content_tag(:li, link_to(label, "##{mid}", class: (active ? 'on' : nil), 'aria-selected': (active ? 'true' : 'false')))
        msecs << content_tag(:div, content_tag(:h2, label, class: 'mnav_tit') + content_tag(:ul, links), id: mid, class: 'mnav_sec')
      end
      if (s = by[:settings])
        caption, url, sel = extract_node_details(s, project)
        lis << content_tag(:li, link_to(caption, url, class: "gnb_trigger is_link#{' selected' if sel}", 'aria-current': (sel ? 'page' : nil)))
        mid = 'mnav_settings'
        mtabs << content_tag(:li, link_to(caption, "##{mid}", class: (sel ? 'on' : nil), 'aria-selected': (sel ? 'true' : 'false')))
        msecs << content_tag(:div, content_tag(:h2, caption, class: 'mnav_tit') + content_tag(:ul, content_tag(:li, krds_link(caption, url, sel, 'gnb_link', :settings))), id: mid, class: 'mnav_sec')
      end
      mobile = content_tag(:div, content_tag(:ul, safe_join(mtabs), class: 'mnav_tabs') + content_tag(:div, safe_join(msecs), class: 'mnav_body'),
                           class: 'mnav', 'aria-label': l(:label_nav_main))
      content_tag(:ul, safe_join(lis), class: 'gnb_menu') + mobile
    end
  end
end
