module MenuItemsHelper
  TYPE_KEYS = %w(list detail form popup tab link).freeze
  CHANNEL_KEYS = %w(both pc mobile).freeze

  def menu_type_options
    TYPE_KEYS.map { |k| [l("label_menu_type_#{k}"), k] }
  end

  def menu_channel_options
    CHANNEL_KEYS.map { |k| [l("label_menu_channel_#{k}"), k] }
  end

  # 표 화면에 넘길 설정 (주소·문구·칼럼)
  def menu_grid_config(columns)
    {
      canEdit: User.current.allowed_to?(:manage_menu_tree, @project),
      canIssue: User.current.allowed_to?(:add_issues, @project) && User.current.allowed_to?(:manage_menu_tree, @project),
      urls: { data: project_menu_items_data_path(@project), create: project_menu_items_path(@project),
              item: project_menu_item_path(@project, 0), move: project_move_menu_item_path(@project, 0), issues: project_menu_items_issues_path(@project),
              issueList: project_issues_path(@project, set_filter: 1, f: ['menu_item_id', 'status_id'], op: { 'menu_item_id' => '=', 'status_id' => '*' }, v: { 'menu_item_id' => ['__ID__'] }),
              newIssue: new_project_issue_path(@project, menu_item_id: '__ID__'), matrix: (project_sys_roles_matrix_path(@project) if @project.module_enabled?(:sys_roles)) },
      columns: columns.map { |c| { id: c.id, name: c.name, kind: c.kind, options: c.option_list } },
      types: menu_type_options.map { |label, key| [key, label] }.to_h,
      channels: menu_channel_options.map { |label, key| [key, label] }.to_h,
      focus: params[:focus].to_i,
      t: %w(depth screen_id url type channel roles active issues progress note add_child add_below indent outdent up down
            delete delete_confirm issues_view issue_new saved error none yes no new_name expand collapse no_rows
            drag select_all done subtotal k_menus k_screens k_linked k_done k_issues k_ratio).to_h { |k| [k, l("label_menu_g_#{k}")] }
    }
  end

  # 구조도 (Mermaid flowchart) — 완료(초록)·진행(파랑)·일감 없음(흰색)·미사용(회색 점선)
  # (classDef 이름은 Mermaid 내부 클래스(.root 등)와 겹치지 않게 mt_ 를 붙임)
  def menu_mermaid(ordered, stats, root: nil, dir: 'LR', depth: nil, show_id: true, hide_unused: false)
    index = ordered.to_h { |m, _| [m.id, m] }
    keep = ordered.select do |m, d|
      next false if depth && d >= depth
      next false if hide_unused && !m.active?
      next true unless root
      node = m
      node = index[node.parent_id] while node && node.parent_id && node.id != root.id
      node&.id == root.id
    end
    ids = keep.map { |m, _| m.id }.to_set
    out = +"flowchart #{dir}\n"
    out << %(  P0(["#{menu_esc(@project.name)}"]):::mt_root\n) unless root
    keep.each do |m, _|
      label = menu_esc(m.name)
      label += "<br/>#{menu_esc(m.screen_id)}" if show_id && m.screen_id
      t = stats[:tree][m.id] || {}
      cls = if !m.active? then 'mt_off'
            elsif t[:total].to_i.zero? then 'mt_todo'
            elsif t[:closed] == t[:total] then 'mt_done'
            else 'mt_prog'
            end
      out << %(  M#{m.id}["#{label}"]:::#{cls}\n)
    end
    keep.each do |m, _|
      if m.parent_id && ids.include?(m.parent_id)
        out << "  M#{m.parent_id} --> M#{m.id}\n"
      elsif !root
        out << "  P0 --> M#{m.id}\n"
      end
    end
    out << "  classDef mt_root fill:#256ef4,stroke:#0b50d0,color:#ffffff\n"
    out << "  classDef mt_done fill:#eaf6ec,stroke:#267337,color:#1e2124\n"
    out << "  classDef mt_prog fill:#ecf2fe,stroke:#256ef4,color:#1e2124\n"
    out << "  classDef mt_todo fill:#ffffff,stroke:#8a949e,color:#1e2124\n"
    out << "  classDef mt_off fill:#f4f5f6,stroke:#b1b8be,stroke-dasharray:4 3,color:#8a949e\n"
    out
  end

  def menu_esc(text)
    text.to_s.tr('"', "'").gsub(/[\r\n]+/, ' ').gsub(/[<>]/, '<' => '‹', '>' => '›')
  end

  def menu_progress_bar(ratio)
    content_tag(:span, class: 'mt_bar', title: "#{ratio}%") { content_tag(:span, '', style: "width:#{ratio.to_i}%") } +
      content_tag(:span, "#{ratio}%", class: 'mt_pct')
  end

  def menu_view_tabs(current)
    items = [[l(:label_menu_view_grid), project_menu_items_path(@project), :grid],
             [l(:label_menu_view_diagram), project_menu_items_diagram_path(@project), :diagram],
             [l(:label_menu_view_status), project_menu_items_status_path(@project), :status]]
    content_tag(:div, class: 'tabs') do
      content_tag(:ul, safe_join(items.map { |label, url, key| content_tag(:li, link_to(label, url, class: (key == current ? 'selected' : nil))) }))
    end
  end
end
