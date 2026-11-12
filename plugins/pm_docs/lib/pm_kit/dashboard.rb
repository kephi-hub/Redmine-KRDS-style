# 프로젝트 개요 위 종합 대시보드 카드 — 켜진 모듈 · 볼 권한이 있는 것만
# 카드: { key:, title:, value:, sub: [문구…], url:, tone: nil|'warn'|'bad', ratio: 0~100|nil }
module PmKit
  module Dashboard
    module_function

    def cards(project, user, h)
      today = User.current.today
      on = ->(mod, perm) { project.module_enabled?(mod) && user.allowed_to?(perm, project) }
      out = []

      if defined?(QaRequirement) && on.(:qa_requirements, :view_qa_requirements)
        reqs = QaRequirement.where(project_id: project.id).alive
        total = reqs.count
        if total.positive?
          ok = reqs.where(status: %w(confirmed changed)).count
          nomenu = defined?(QaRequirementMenu) && project.module_enabled?(:menu_tree) ? reqs.where.not(id: QaRequirementMenu.select(:qa_requirement_id)).count : 0
          out << { key: 'req', title: '요구사항', value: "#{ok} / #{total}", ratio: ok * 100 / total, url: h.project_qa_requirements_path(project),
                   sub: ['확정', (nomenu.positive? ? "메뉴 미연결 #{nomenu}" : nil)].compact, tone: nomenu.positive? ? 'warn' : nil }
        end
      end

      if on.(:programs, :view_programs)
        ps = PmProgram.where(project_id: project.id)
        total = ps.count
        if total.positive?
          done = ps.where(status: %w(done tested)).count
          out << { key: 'prog', title: '프로그램', value: "#{done} / #{total}", ratio: done * 100 / total, url: h.project_pm_programs_path(project),
                   sub: ['개발 완료', "단위테스트 완료 #{ps.where(status: 'tested').count}"] }
        end
      end

      if defined?(QaTestRun) && on.(:qa_tests, :view_qa_tests)
        run = QaTestRun.where(project_id: project.id).sorted.first
        if run
          res = run.qa_test_results.to_a
          counted = res.reject { |r| r.result == 'skip' }
          pass = counted.count { |r| r.result == 'pass' }
          open_defects = res.select(&:issue_id).count { |r| r.issue && !r.issue.closed? }
          out << { key: 'test', title: "테스트 · #{run.name}", value: counted.any? ? "#{pass * 100 / counted.size}%" : '-', ratio: counted.any? ? pass * 100 / counted.size : 0,
                   url: h.project_qa_test_run_path(project, run), sub: ["합격 #{pass} / #{counted.size}", (open_defects.positive? ? "미조치 결함 #{open_defects}" : nil)].compact,
                   tone: open_defects.positive? ? 'bad' : nil }
        end
      end

      if on.(:risks, :view_risks)
        rs = PmRisk.where(project_id: project.id).to_a.select(&:open?)
        high = rs.count { |r| r.level == 'high' }
        out << { key: 'risk', title: '이슈 · 위험', value: rs.size.to_s, url: h.project_pm_risks_path(project),
                 sub: ['대응 필요', (high.positive? ? "등급 상 #{high}" : nil)].compact, tone: high.positive? ? 'bad' : nil }
      end

      if on.(:deliverables, :view_deliverables)
        ds = PmDeliverable.where(project_id: project.id).to_a
        if ds.any?
          req = ds.select(&:required)
          sub = req.count { |d| d.status == 'submitted' }
          late = ds.count { |d| d.late?(today) }
          out << { key: 'deliv', title: '산출물', value: "#{sub} / #{req.size}", ratio: req.any? ? sub * 100 / req.size : 0, url: h.project_pm_deliverables_path(project),
                   sub: ['필수 제출', (late.positive? ? "마감 지남 #{late}" : nil)].compact, tone: late.positive? ? 'bad' : nil }
        end
      end

      if on.(:change_requests, :view_change_requests)
        cs = PmChangeRequest.where(project_id: project.id)
        pending = cs.where(status: %w(received analyzing)).count
        out << { key: 'cr', title: '변경요청', value: pending.to_s, url: h.project_pm_change_requests_path(project),
                 sub: ['결정 대기', "승인 후 반영 중 #{cs.where(status: 'approved').count}"] } if cs.exists?
      end

      if project.module_enabled?(:issue_tracking) && user.allowed_to?(:view_issues, project)
        open = Issue.visible(user).where(project_id: project.id).open
        week = open.where(due_date: today..today.end_of_week).count
        over = open.where('due_date < ?', today).count
        out << { key: 'issue', title: '일감', value: week.to_s, url: h.project_issues_path(project, set_filter: 1, sort: 'due_date'),
                 sub: ['이번 주 마감', (over.positive? ? "기한 지남 #{over}" : nil)].compact, tone: over.positive? ? 'bad' : nil }
        if (sr = project.trackers.find_by(name: 'SR'))
          s = sr_stats(project, user, sr, today)
          out << { key: 'sr', title: 'SR (서비스 요청)', value: s[:open].to_s, url: h.project_issues_path(project, set_filter: 1, tracker_id: sr.id),
                   sub: ['처리 중', (s[:over].positive? ? "기한 지남 #{s[:over]}" : nil), (s[:rate] ? "이번 달 준수율 #{s[:rate]}%" : nil)].compact,
                   tone: s[:over].positive? ? 'bad' : nil }
        end
      end

      if defined?(PmAudit) && on.(:audits, :view_audits)
        open = PmAudit.where(project_id: project.id).where.not(status: %w(verified)).count
        out << { key: 'audit', title: '감리 지적사항', value: open.to_s, url: h.project_pm_audits_path(project), sub: ['미확인'], tone: open.positive? ? 'warn' : nil } if PmAudit.where(project_id: project.id).exists?
      end
      out
    end

    # SR: 처리 중 · 기한 지남 · 이번 달 완료 중 기한 준수율
    def sr_stats(project, user, tracker, today)
      scope = Issue.visible(user).where(project_id: project.id, tracker_id: tracker.id)
      open = scope.open
      closed = scope.joins(:status).where(issue_statuses: { is_closed: true }).where(closed_on: today.beginning_of_month.beginning_of_day..today.end_of_day).where.not(due_date: nil).to_a
      ok = closed.count { |i| i.closed_on.to_date <= i.due_date }
      { open: open.count, over: open.where('due_date < ?', today).count, rate: closed.any? ? ok * 100 / closed.size : nil }
    end
  end
end
