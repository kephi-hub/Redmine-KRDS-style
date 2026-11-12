# 주간·월간 보고서 — 기간 안의 일감 실적 · 다음 기간 계획 · 이슈·위험 · 변경요청 · 산출물 · 테스트·결함 · SR·SLA · 투입 인력 · 감리
# 켜진 모듈만 (볼 수 있는 일감만). 엑셀은 PmKit::Sheet.report
module PmKit
  module Report
    module_function

    # 이번 주(월~일) · 지난주 · 이번 달 · 지난달
    def period(kind, today = User.current.today)
      case kind
      when 'last_week' then [today.beginning_of_week - 7, today.beginning_of_week - 1]
      when 'month' then [today.beginning_of_month, today.end_of_month]
      when 'last_month' then [today.prev_month.beginning_of_month, today.prev_month.end_of_month]
      else [today.beginning_of_week, today.end_of_week]
      end
    end

    def issue_row(i)
      ["##{i.id}", i.tracker.name, i.subject, i.status.name, i.assigned_to&.name, "#{i.closed? ? 100 : i.done_ratio}%", i.start_date&.to_s, i.due_date&.to_s]
    end

    def build(project, from, to, user = User.current)
      len = (to - from).to_i + 1
      nfrom = to + 1
      nto = to + len
      on = ->(mod) { project.module_enabled?(mod) }
      r = { from: from, to: to, next_from: nfrom, next_to: nto, sections: [] }
      issues = on.(:issue_tracking) ? Issue.visible(user).where(project_id: project.id).includes(:tracker, :status, :assigned_to) : Issue.none
      closed = issues.where(closed_on: from.beginning_of_day..to.end_of_day).to_a
      progress = issues.open.where(updated_on: from.beginning_of_day..to.end_of_day).to_a
      plan = issues.open.where('(start_date BETWEEN :a AND :b) OR (due_date BETWEEN :a AND :b)', a: nfrom, b: nto).to_a
      late = issues.open.where('due_date < ?', to + 1).to_a
      all = issues.to_a
      ratio = all.any? ? (all.sum { |i| i.closed? ? 100 : i.done_ratio.to_i } / all.size.to_f).round : 0
      r[:summary] = [['보고 기간', "#{from} ~ #{to}"], ['일감 전체 진척률', "#{ratio}%"], ['기간 완료 일감', closed.size], ['기간 진행 일감', progress.size],
                     ['다음 기간 계획 일감', plan.size], ['기한 지난 일감', late.size]]
      r[:done] = closed.sort_by(&:id).map { |i| issue_row(i) + ['완료'] } + progress.sort_by(&:id).map { |i| issue_row(i) + ['진행'] }
      r[:plan] = plan.sort_by { |i| [i.start_date || i.due_date || nto, i.id] }.map { |i| issue_row(i) }
      r[:late] = late.sort_by { |i| i.due_date }.map { |i| issue_row(i) }
      if (versions = project.shared_versions.open.to_a).any?
        r[:versions] = versions.map { |v| [v.name, v.effective_date&.to_s, "#{v.completed_percent.round}%", v.fixed_issues.count] }
      end
      if on.(:risks)
        rs = PmRisk.where(project_id: project.id).includes(:owner).to_a
        r[:risks] = rs.select(&:open?).sort_by { |x| [-x.score, x.code] }.map { |x| [x.code, Sheet::LABEL['rkind'][x.kind], x.title, Sheet::LABEL['level'][x.level], Sheet::LABEL['rstatus'][x.status], x.owner&.name, x.due_on&.to_s, x.plan] }
        r[:summary] << ['열린 이슈·위험', r[:risks].size]
      end
      if on.(:change_requests)
        cs = PmChangeRequest.where(project_id: project.id).where('(requested_on BETWEEN :a AND :b) OR (decided_on BETWEEN :a AND :b) OR status IN (:open)', a: from, b: to, open: %w(received analyzing)).order(:code).to_a
        r[:crs] = cs.map { |c| [c.code, c.title, Sheet::LABEL['crstatus'][c.status], c.requested_on&.to_s, c.decided_on&.to_s, c.effort&.to_f, c.schedule_impact] }
      end
      if on.(:deliverables)
        ds = PmDeliverable.where(project_id: project.id).includes(:owner).sorted.to_a
        sel = ds.select { |d| (d.submitted_on && d.submitted_on.between?(from, to)) || d.late?(to) || (d.due_on && d.due_on.between?(nfrom, nto)) }
        r[:deliverables] = sel.map { |d| [d.code, d.name, Sheet::LABEL['dstatus'][d.status], d.owner&.name, d.due_on&.to_s, d.submitted_on&.to_s,
                                         d.late?(to) ? '마감 지남' : (d.submitted_on&.between?(from, to) ? '기간 제출' : '다음 기간 마감')] }
        r[:summary] << ['산출물 마감 지남', ds.count { |d| d.late?(to) }]
      end
      if defined?(QaTestRun) && on.(:qa_tests)
        res = QaTestResult.joins(:qa_test_run).where(qa_test_runs: { project_id: project.id }).where(tested_at: from.beginning_of_day..to.end_of_day).to_a
        defect_tracker = project.trackers.find_by(name: '결함')
        dsc = defect_tracker ? issues.where(tracker_id: defect_tracker.id) : Issue.none
        r[:tests] = [['기간 수행', res.size], ['합격', res.count { |x| x.result == 'pass' }], ['불합격', res.count { |x| x.result == 'fail' }],
                     ['기간 등록 결함', dsc.where(created_on: from.beginning_of_day..to.end_of_day).count], ['기간 조치 결함', dsc.where(closed_on: from.beginning_of_day..to.end_of_day).count],
                     ['미조치 결함', dsc.open.count]]
      end
      if on.(:issue_tracking) && (sr = project.trackers.find_by(name: Sla::TRACKER))
        srs = issues.where(tracker_id: sr.id)
        recv = srs.where(created_on: from.beginning_of_day..to.end_of_day).to_a
        done = srs.where(closed_on: from.beginning_of_day..to.end_of_day).where.not(due_date: nil).to_a
        ok = done.count { |i| i.closed_on.to_date <= i.due_date }
        cf = Sla.field
        r[:sr] = { summary: [['기간 접수', recv.size], ['기간 완료', done.size], ['기한 준수', ok], ['기한 준수율', done.any? ? "#{ok * 100 / done.size}%" : '-'],
                             ['처리 중', srs.open.count], ['처리 중 기한 지남', srs.open.where('due_date < ?', to + 1).count]],
                   rows: (recv | done).sort_by(&:id).map { |i| issue_row(i) + [cf ? i.custom_field_value(cf) : nil, i.closed? && i.due_date ? (i.closed_on.to_date <= i.due_date ? '준수' : '초과') : nil] } }
      end
      if on.(:staff) && user.allowed_to?(:view_staff, project)
        st = PmStaff.where(project_id: project.id).includes(:user).sorted.to_a.select { |s| s.plan_mm(from, to).positive? || s.actual_mm(from, to).to_f.positive? }
        r[:staff] = st.map { |s| [s.name, Sheet::LABEL['srole'][s.role], s.company, s.plan_mm(from, to), s.actual_mm(from, to)] }
      end
      if on.(:audits)
        au = PmAudit.where(project_id: project.id).includes(:pm_audit_round, :owner).sorted.to_a
        r[:audits] = au.select { |a| a.open? || (a.done_on && a.done_on.between?(from, to)) }.map { |a| [a.code, a.pm_audit_round&.name, a.title, Sheet::LABEL['astatus'][a.status], a.owner&.name, a.due_on&.to_s, a.late?(to) ? '기한 지남' : nil] }
        r[:summary] << ['감리 미확인 지적', au.count(&:open?)]
      end
      r
    end
  end
end
