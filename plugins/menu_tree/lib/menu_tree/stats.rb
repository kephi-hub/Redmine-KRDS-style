# 메뉴별 일감 현황 (볼 수 있는 일감만) — 닫힌 일감은 100%, 나머지는 진행률(%)
# own: 그 메뉴에 직접 연결된 일감, tree: 하위 메뉴까지 합친 일감(같은 일감은 한 번만)
module MenuTree
  module Stats
    module_function

    def build(ordered)
      menus = ordered.map(&:first)
      ids = menus.map(&:id)
      return { own: {}, tree: {}, issues: {} } if ids.empty?
      rows = Issue.visible.joins(:menu_item_issues, :status).where(menu_item_issues: { menu_item_id: ids })
                  .pluck('menu_item_issues.menu_item_id', 'issues.id', 'issues.done_ratio', 'issue_statuses.is_closed', 'issues.assigned_to_id')
      issues = {}
      links = Hash.new { |h, k| h[k] = [] }
      rows.each do |mid, iid, done, closed, uid|
        issues[iid] = { done: closed ? 100 : done.to_i, closed: closed, user: uid }
        links[mid] << iid
      end
      names = Principal.where(id: issues.values.map { |i| i[:user] }.compact.uniq).to_h { |u| [u.id, u.name] }
      issues.each_value { |i| i[:user_name] = names[i[:user]] }
      by_parent = menus.group_by(&:parent_id)
      tree_ids = {}
      collect = lambda do |m|
        tree_ids[m.id] ||= (by_parent[m.id] || []).reduce(links.fetch(m.id, []).uniq) { |acc, c| acc | collect.call(c) }
      end
      menus.each { |m| collect.call(m) }
      # 일감이 없는 메뉴는 own 에 넣지 않음 (현황의 '일감 연결 화면'·'완료 화면' 계산 기준)
      { own: links.select { |_, l| l.any? }.transform_values { |l| summarize(l.uniq, issues) }, tree: tree_ids.transform_values { |l| summarize(l, issues) }, issues: issues }
    end

    def summarize(issue_ids, issues)
      return { total: 0, closed: 0, ratio: 0, users: [], issue_ids: [] } if issue_ids.empty?
      list = issue_ids.map { |i| issues[i] }
      { total: list.size, closed: list.count { |i| i[:closed] }, ratio: (list.sum { |i| i[:done] } / list.size.to_f).round,
        users: list.map { |i| i[:user_name] }.compact.uniq, issue_ids: issue_ids }
    end
  end
end
