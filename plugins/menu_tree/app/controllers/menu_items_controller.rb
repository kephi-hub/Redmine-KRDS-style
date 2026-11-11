# 프로젝트 > 메뉴 구조도 — 엑셀형 표(화면에서 JSON 으로 고침), 구조도, 현황, 엑셀 가져오기·내보내기, 일감 일괄 생성
require 'csv'

class MenuItemsController < ApplicationController
  menu_item :menu_items
  helper :menu_items

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_menu, only: [:update, :move, :destroy]

  FIELDS = %w(name screen_id url screen_type channel active note).freeze

  def index
    @columns = MenuColumn.where(project_id: @project.id).sorted.to_a
  end

  # 표 데이터 (화면 스크립트가 읽음)
  def data
    render json: grid_data
  end

  # 새 메뉴: parent_id 아래 맨 끝, after_id 가 있으면 그 메뉴 바로 다음
  def create
    parent = params[:parent_id].present? ? scope.find(params[:parent_id]) : nil
    after = params[:after_id].present? ? scope.find(params[:after_id]) : nil
    parent = after.parent if after
    menu = MenuItem.new(project: @project, parent: parent, name: params[:name].presence || l(:label_menu_new_name), author_id: User.current.id)
    MenuItem.transaction do
      siblings = scope.where(parent_id: parent&.id)
      if after
        siblings.where('position > ?', after.position).update_all('position = position + 1')
        menu.position = after.position + 1
      else
        menu.position = (siblings.maximum(:position) || 0) + 1
      end
      menu.save!
    end
    render json: { ok: true, id: menu.id }
  rescue ActiveRecord::RecordInvalid => e
    render json: { ok: false, message: e.record.errors.full_messages.join(', ') }, status: 422
  end

  # 칸 하나 고치기: field=name|screen_id|url|screen_type|channel|active|note|x<칼럼 id>
  def update
    field = params[:field].to_s
    value = params[:value]
    if (cid = field[/\Ax(\d+)\z/, 1])
      col = MenuColumn.find_by(id: cid, project_id: @project.id)
      return render(json: { ok: false, message: l(:error_menu_bad_field) }, status: 422) unless col
      extra = @menu.extra.dup
      (v = col.cast(value)) ? extra[cid] = v : extra.delete(cid)
      @menu.extra = extra
    elsif FIELDS.include?(field)
      value = value.to_s == '1' || value.to_s == 'true' if field == 'active'
      @menu.send("#{field}=", value)
    else
      return render(json: { ok: false, message: l(:error_menu_bad_field) }, status: 422)
    end
    if @menu.save
      render json: { ok: true }
    else
      render json: { ok: false, message: @menu.errors.full_messages.join(', ') }, status: 422
    end
  end

  # 구조 바꾸기: op=indent|outdent|up|down|drop(target_id, where=before|after|inside)
  def move
    MenuItem.transaction do
      siblings = ->(pid) { scope.where(parent_id: pid).where.not(id: @menu.id).order(:position, :id).to_a }
      case params[:op]
      when 'indent'
        prev = scope.where(parent_id: @menu.parent_id).where('position < ? OR (position = ? AND id < ?)', @menu.position, @menu.position, @menu.id).order(:position, :id).last
        raise ArgumentError, l(:error_menu_cannot_indent) unless prev
        place(@menu, prev.id, siblings.call(prev.id), nil)
      when 'outdent'
        raise ArgumentError, l(:error_menu_cannot_outdent) unless @menu.parent
        parent = @menu.parent
        list = siblings.call(parent.parent_id)
        place(@menu, parent.parent_id, list, list.index(parent) + 1)
      when 'up', 'down'
        list = siblings.call(@menu.parent_id)
        mine = scope.where(parent_id: @menu.parent_id).order(:position, :id).to_a.index(@menu)
        pos = params[:op] == 'up' ? [mine - 1, 0].max : [mine + 1, list.size].min
        place(@menu, @menu.parent_id, list, pos)
      when 'drop'
        target = scope.find(params[:target_id])
        by_parent = scope.to_a.group_by(&:parent_id)
        raise ArgumentError, l(:error_menu_cycle) if target.id == @menu.id || @menu.descendant_ids(by_parent).include?(target.id)
        if params[:where] == 'inside'
          place(@menu, target.id, siblings.call(target.id), nil)
        else
          list = siblings.call(target.parent_id)
          idx = list.index(target)
          place(@menu, target.parent_id, list, params[:where] == 'before' ? idx : idx + 1)
        end
      else
        raise ArgumentError, l(:error_menu_bad_field)
      end
    end
    render json: { ok: true }
  rescue ArgumentError, ActiveRecord::RecordNotFound => e
    render json: { ok: false, message: e.message }, status: 422
  end

  def destroy
    @menu.destroy
    render json: { ok: true }
  end

  # 구조도 (Mermaid flowchart)
  def diagram
    @ordered = MenuItem.ordered(@project)
    @roots = @ordered.select { |_, d| d.zero? }.map(&:first)
    @root = @roots.find { |m| m.id.to_s == params[:root].to_s }
    @dir = %w(LR TD).include?(params[:dir]) ? params[:dir] : 'LR'
    @depth = params[:depth].to_i.positive? ? params[:depth].to_i : nil
    @show_id = params.key?(:applied) ? params[:show_id] == '1' : true
    @hide_unused = params[:hide_unused] == '1'
    @stats = MenuTree::Stats.build(@ordered)
    @mermaid = helpers.menu_mermaid(@ordered, @stats, root: @root, dir: @dir, depth: @depth, show_id: @show_id, hide_unused: @hide_unused)
    base = "메뉴구조도_#{@project.identifier}_#{User.current.today.strftime('%Y%m%d')}"
    case params[:download]
    when 'mmd' then send_data @mermaid, filename: "#{base}.mmd", type: 'text/plain; charset=utf-8'
    when 'md'
      md = "# #{@project.name} 메뉴 구조도\n\n- 생성: #{format_time(Time.now)} · 메뉴 #{@ordered.size}\n\n```mermaid\n#{@mermaid}```\n"
      send_data md, filename: "#{base}.md", type: 'text/markdown; charset=utf-8'
    end
  end

  # 현황: 1뎁스별 화면(말단 메뉴) 수·일감 연결·완료·진행률
  def status
    @ordered = MenuItem.ordered(@project)
    @stats = MenuTree::Stats.build(@ordered)
    by_parent = @ordered.map(&:first).group_by(&:parent_id)
    @leaves = @ordered.reject { |m, _| by_parent[m.id] }.map(&:first)
    @root_of = {}
    @ordered.each { |m, d| @root_of[m.id] = d.zero? ? m : @root_of[m.parent_id] }
    @index = @ordered.to_h { |m, _| [m.id, m] }
  end

  def export
    ordered = MenuItem.ordered(@project)
    columns = MenuColumn.where(project_id: @project.id).sorted.to_a
    stats = MenuTree::Stats.build(ordered)[:own]
    roles = role_summary(ordered.map { |m, _| m.id })
    header, rows, depth = MenuTree::Sheet.export(@project, ordered, columns, stats, roles)
    widths = Array.new(depth, 18) + [16, 30, 10, 8, 6] + columns.map { 14 } + (roles ? [28] : []) + [8, 6, 8, 30]
    data = KrdsUi::Xlsx.build([{ name: '메뉴 구조도', header: header, rows: rows, widths: widths }])
    send_data data, filename: "메뉴구조도_#{@project.identifier}_#{User.current.today.strftime('%Y%m%d')}.xlsx",
                    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  end

  # 엑셀(xlsx)·CSV 가져오기 — 내보내기 파일 양식 그대로
  def import
    return unless request.post?
    file = params[:file]
    return import_error(l(:error_menu_no_file)) unless file.respond_to?(:read)
    raw = file.read
    rows = if raw.start_with?("PK")
             KrdsUi::XlsxReader.read(raw)
           else
             text = raw.dup.force_encoding('UTF-8').delete_prefix("﻿")
             text = raw.dup.force_encoding('CP949').encode('UTF-8', invalid: :replace, undef: :replace) unless text.valid_encoding?
             CSV.parse(text) rescue nil
           end
    return import_error(l(:error_menu_bad_file)) if rows.blank?
    @result = MenuTree::Sheet.import(@project, rows, replace: params[:mode] == 'replace', author: User.current, new_columns: params[:new_columns] == '1')
    return import_error(l(:error_menu_no_depth)) unless @result
    flash.now[:notice] = l(:notice_menu_imported, created: @result[:created], updated: @result[:updated])
  rescue ActiveRecord::RecordInvalid => e
    import_error(e.record.errors.full_messages.join(', '))
  end

  # 고른 메뉴마다 일감 만들기 (이미 일감이 있는 메뉴는 건너뛰기 선택)
  def issues
    return render(json: { ok: false, message: l(:notice_not_authorized) }, status: 403) unless User.current.allowed_to?(:add_issues, @project)
    menus = scope.where(id: Array(params[:ids]).map(&:to_i)).to_a
    index = scope.index_by(&:id)
    tracker = @project.trackers.find_by(id: params[:tracker_id]) || @project.trackers.first
    linked = MenuItemIssue.where(menu_item_id: menus.map(&:id)).distinct.pluck(:menu_item_id)
    created = 0; skipped = 0; errors = []
    order = MenuItem.ordered(@project).each_with_index.to_h { |(m, _), i| [m.id, i] }
    menus.sort_by { |m| order[m.id] || 0 }.each do |m|
      if params[:skip_linked] == '1' && linked.include?(m.id)
        skipped += 1
        next
      end
      issue = Issue.new(project: @project, tracker: tracker, author: User.current)
      issue.subject = subject_for(m, index, params[:subject_format]).truncate(255)
      issue.description = [l(:label_menu_item) + ': ' + m.path(index), (m.screen_id && "#{l(:field_menu_screen_id)}: #{m.screen_id}"), (m.url && "URL: #{m.url}")].compact.join("\n")
      issue.assigned_to_id = params[:assigned_to_id] if params[:assigned_to_id].present?
      issue.parent_issue_id = params[:parent_issue_id] if params[:parent_issue_id].present?
      issue.start_date = params[:start_date] if params[:start_date].present?
      issue.due_date = params[:due_date] if params[:due_date].present?
      if issue.save
        MenuItemIssue.create!(menu_item_id: m.id, issue_id: issue.id)
        created += 1
      else
        errors << "#{m.name}: #{issue.errors.full_messages.join(', ')}"
      end
    end
    render json: { ok: errors.empty?, created: created, skipped: skipped, errors: errors.first(10),
                   message: l(:notice_menu_issues_created, created: created, skipped: skipped) }
  end

  private

  def scope
    MenuItem.where(project_id: @project.id)
  end

  def find_menu
    @menu = scope.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # 형제 목록(list, 자신 제외)의 idx 위치에 넣고 순서 다시 매김
  def place(menu, parent_id, list, idx)
    idx ||= list.size
    list.insert(idx, menu)
    menu.parent_id = parent_id
    menu.save!
    list.each_with_index { |m, i| m.update_column(:position, i + 1) if m.position != i + 1 || m.id == menu.id }
  end

  def subject_for(menu, index, format)
    path = menu.path(index)
    case format
    when 'name' then menu.name
    when 'id_name' then [menu.screen_id && "[#{menu.screen_id}]", menu.name].compact.join(' ')
    else [menu.screen_id && "[#{menu.screen_id}]", path].compact.join(' ')
    end
  end

  def import_error(message)
    flash.now[:error] = message
    render :import
  end

  def sys_roles_on?
    @project.module_enabled?(:sys_roles) && User.current.allowed_to?(:view_sys_roles, @project)
  end

  # { 메뉴 id => [[권한 이름, 'R'|'CRU'|'CRUD'], …] } (시스템 권한 모듈이 꺼져 있으면 nil)
  def role_summary(ids)
    return nil unless sys_roles_on?
    roles = SysRole.where(project_id: @project.id).active.sorted.to_a
    order = roles.map(&:id)
    names = roles.index_by(&:id)
    MenuRoleAccess.where(menu_item_id: ids, sys_role_id: order).to_a.group_by(&:menu_item_id).transform_values do |list|
      list.sort_by { |a| order.index(a.sys_role_id) }.map { |a| [names[a.sys_role_id].name, MenuRoleAccess::CODES[a.access]] }
    end
  end

  def grid_data
    ordered = MenuItem.ordered(@project)
    stats = MenuTree::Stats.build(ordered)
    roles = role_summary(ordered.map { |m, _| m.id })
    parents = ordered.map { |m, _| m.parent_id }.compact.to_set
    {
      rows: ordered.map do |m, d|
        own = stats[:own][m.id]
        tree = stats[:tree][m.id]
        { id: m.id, parent_id: m.parent_id, depth: d, name: m.name, screen_id: m.screen_id, url: m.url, screen_type: m.screen_type,
          channel: m.channel, active: m.active, note: m.note, extra: m.extra, has_children: parents.include?(m.id),
          own: own && own.slice(:total, :closed, :ratio, :users), tree: tree && tree[:total].positive? ? tree.slice(:total, :closed, :ratio) : nil,
          roles: roles ? (roles[m.id] || []) : nil }
      end,
      max_depth: (ordered.map(&:last).max || 0) + 1
    }
  end
end
