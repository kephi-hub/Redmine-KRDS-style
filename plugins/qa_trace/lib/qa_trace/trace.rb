# 추적 계산 — 요구사항마다 메뉴(하위 메뉴 포함)·일감·테스트 케이스(직접 연결 + 메뉴를 거친 연결)와 최근 결과
module QaTrace
  module Trace
    module_function

    # 케이스별 가장 최근 결과 { case_id => QaTestResult } (미수행 제외)
    def latest_results(project)
      QaTestResult.joins(:qa_test_run).where(qa_test_runs: { project_id: project.id }).where.not(result: 'none')
                  .includes(:issue).to_a.sort_by { |r| [r.tested_at || Time.at(0), r.id] }.index_by(&:qa_test_case_id)
    end

    def menus_on?(project)
      project.module_enabled?(:menu_tree)
    end

    # { 요구사항 id => { menus:, issues:, issues_closed:, cases:, results:, pass:, fail:, untested:, state:, risks: } }
    def build(project, reqs, latest = nil)
      ids = reqs.map(&:id)
      menus = menus_on?(project) ? MenuItem.where(project_id: project.id).to_a : []
      index = menus.index_by(&:id)
      by_parent = menus.group_by(&:parent_id)
      req_menus = pairs(QaRequirementMenu.where(qa_requirement_id: ids).pluck(:qa_requirement_id, :menu_item_id))
      req_issues = pairs(QaRequirementIssue.where(qa_requirement_id: ids).pluck(:qa_requirement_id, :issue_id))
      issues = Issue.where(id: req_issues.values.flatten.uniq).includes(:status).index_by(&:id)
      cases = QaTestCase.where(project_id: project.id).active.to_a
      case_index = cases.index_by(&:id)
      by_menu = cases.group_by(&:menu_item_id)
      direct = pairs(QaCaseRequirement.where(qa_requirement_id: ids).pluck(:qa_requirement_id, :qa_test_case_id))
      latest ||= latest_results(project)
      reqs.to_h do |r|
        mids = (req_menus[r.id] || []).select { |m| index[m] }
        all_mids = mids.flat_map { |m| [m] + index[m].descendant_ids(by_parent) }.uniq
        cs = ((direct[r.id] || []).filter_map { |c| case_index[c] } + all_mids.flat_map { |m| by_menu[m] || [] }).uniq.sort_by(&:code)
        is = (req_issues[r.id] || []).filter_map { |i| issues[i] }.sort_by(&:id)
        results = cs.to_h { |c| [c.id, latest[c.id]] }
        res = results.values.map { |x| x&.result || 'none' }
        info = { menus: mids.map { |m| index[m] }, menu_index: index, issues: is, issues_closed: is.count(&:closed?), cases: cs,
                 results: results, pass: res.count('pass'), fail: res.count('fail'), untested: res.count('none'),
                 skip: res.count('skip') }
        info[:state] = state(info)
        info[:risks] = risks(r, info)
        [r.id, info]
      end
    end

    def pairs(list)
      list.group_by(&:first).transform_values { |l| l.map(&:last) }
    end

    # 테스트 상태: none(케이스 없음) / fail / pass(제외 빼고 모두 합격) / progress
    def state(info)
      return 'none' if info[:cases].empty?
      return 'fail' if info[:fail].positive?
      counted = info[:cases].size - info[:skip]
      return 'pass' if counted.positive? && info[:pass] == counted
      'progress'
    end

    def risks(req, info)
      return(info[:issues].any? { |i| !i.closed? } ? %w(deleted_open) : []) if req.deleted?
      out = []
      out << 'no_menu' if info[:menus].empty?
      out << 'no_test' if info[:cases].empty?
      out << 'fail' if info[:fail].positive?
      out
    end
  end
end
