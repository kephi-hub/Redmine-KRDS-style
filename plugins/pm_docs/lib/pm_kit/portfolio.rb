# 전체 프로젝트 현황 (PMO) — 사용자가 볼 수 있는 진행 중 프로젝트마다 지표 한 줄 + 신호등
# 지표는 모듈이 켜져 있고 그 사용자에게 보기 권한이 있을 때만 (없으면 nil → 화면 '-')
# 신호등: 적(위험) · 황(주의) · 녹(정상) — RULES 참고, 이유도 함께
module PmKit
  module Portfolio
    module_function

    # [신호, 조건, 이유] — 위에서부터, 적이 하나라도 있으면 적
    RULES = [
      ['red', ->(m) { m[:gap] && m[:gap] <= -20 }, ->(m) { "진척이 경과보다 #{-m[:gap]}%p 늦음" }],
      ['red', ->(m) { m[:risk_high].to_i.positive? }, ->(m) { "위험 등급 상 #{m[:risk_high]}" }],
      ['red', ->(m) { m[:overdue].to_i >= 5 }, ->(m) { "기한 지난 일감 #{m[:overdue]}" }],
      ['red', ->(m) { m[:sr_over].to_i.positive? }, ->(m) { "SR 기한 지남 #{m[:sr_over]}" }],
      ['red', ->(m) { m[:deliv_late].to_i >= 3 }, ->(m) { "산출물 마감 지남 #{m[:deliv_late]}" }],
      ['yellow', ->(m) { m[:gap] && m[:gap] <= -10 }, ->(m) { "진척이 경과보다 #{-m[:gap]}%p 늦음" }],
      ['yellow', ->(m) { m[:overdue].to_i.positive? }, ->(m) { "기한 지난 일감 #{m[:overdue]}" }],
      ['yellow', ->(m) { m[:deliv_late].to_i.positive? }, ->(m) { "산출물 마감 지남 #{m[:deliv_late]}" }],
      ['yellow', ->(m) { m[:defects].to_i.positive? }, ->(m) { "미조치 결함 #{m[:defects]}" }],
      ['yellow', ->(m) { m[:audit_late].to_i.positive? }, ->(m) { "감리 조치 기한 지남 #{m[:audit_late]}" }]
    ].freeze

    def projects(user)
      Project.visible(user).where(status: Project::STATUS_ACTIVE).sorted.to_a
    end

    def rows(user = User.current, today = User.current.today)
      projects(user).map { |p| metrics(p, user, today) }
    end

    def metrics(p, user, today)
      on = ->(mod, perm) { p.module_enabled?(mod) && user.allowed_to?(perm, p) }
      m = { project: p }
      if on.(:issue_tracking, :view_issues)
        issues = Issue.visible(user).where(project_id: p.id)
        all = issues.joins(:status).pluck(:start_date, :due_date, :done_ratio, 'issue_statuses.is_closed')
        if all.any?
          m[:issues] = all.size
          m[:progress] = (all.sum { |_, _, r, c| c ? 100 : r.to_i } / all.size.to_f).round
          starts = all.map(&:first).compact
          ends = all.map { |x| x[1] }.compact + p.shared_versions.where(project_id: p.id).pluck(:effective_date).compact
          m[:start_on] = starts.min
          m[:end_on] = ends.max
          if m[:start_on] && m[:end_on] && m[:end_on] > m[:start_on]
            m[:elapsed] = (((today - m[:start_on]).to_f / (m[:end_on] - m[:start_on])) * 100).round.clamp(0, 100)
            m[:gap] = m[:progress] - m[:elapsed]
          end
        end
        open = issues.open
        m[:overdue] = open.where('due_date < ?', today).count
        m[:due_week] = open.where(due_date: today..today.end_of_week).count
        if (sr = p.trackers.find_by(name: Sla::TRACKER))
          s = Dashboard.sr_stats(p, user, sr, today)
          m[:sr_open], m[:sr_over], m[:sr_rate] = s[:open], s[:over], s[:rate]
        end
      end
      if defined?(QaRequirement) && on.(:qa_requirements, :view_qa_requirements)
        reqs = QaRequirement.where(project_id: p.id).alive
        m[:req_total] = reqs.count
        m[:req_ok] = reqs.where(status: %w(confirmed changed)).count
      end
      if on.(:programs, :view_programs)
        ps = PmProgram.where(project_id: p.id)
        m[:prog_total] = ps.count
        m[:prog_done] = ps.where(status: %w(done tested)).count
      end
      if defined?(QaTestRun) && on.(:qa_tests, :view_qa_tests) && (run = QaTestRun.where(project_id: p.id).sorted.first)
        res = run.qa_test_results.includes(:issue).to_a
        counted = res.reject { |r| r.result == 'skip' }
        m[:test_rate] = counted.any? ? counted.count { |r| r.result == 'pass' } * 100 / counted.size : nil
        m[:defects] = res.count { |r| r.issue && !r.issue.closed? }
      end
      if on.(:risks, :view_risks)
        rs = PmRisk.where(project_id: p.id).to_a.select(&:open?)
        m[:risk_open] = rs.size
        m[:risk_high] = rs.count { |r| r.level == 'high' }
      end
      if on.(:deliverables, :view_deliverables)
        ds = PmDeliverable.where(project_id: p.id).to_a
        req = ds.select(&:required)
        m[:deliv_req] = req.size
        m[:deliv_sub] = req.count { |d| d.status == 'submitted' }
        m[:deliv_late] = ds.count { |d| d.late?(today) }
      end
      m[:cr_wait] = PmChangeRequest.where(project_id: p.id, status: %w(received analyzing)).count if on.(:change_requests, :view_change_requests)
      if on.(:audits, :view_audits)
        au = PmAudit.where(project_id: p.id).to_a
        m[:audit_open] = au.count(&:open?)
        m[:audit_late] = au.count { |a| a.late?(today) }
      end
      if on.(:staff, :view_staff)
        st = PmStaff.where(project_id: p.id).to_a
        m[:staff_now] = st.count { |s| s.active?(today) }
        m[:mm_month] = st.sum { |s| s.plan_mm(today.beginning_of_month, today.end_of_month) }.round(1)
      end
      m[:signal], m[:reasons] = signal(m)
      m
    end

    def signal(m)
      hits = RULES.select { |_, cond, _| cond.(m) }
      level = hits.any? { |l, _, _| l == 'red' } ? 'red' : (hits.any? ? 'yellow' : 'green')
      [level, hits.map { |_, _, why| why.(m) }.uniq]
    end

    SIGNAL = { 'red' => '위험', 'yellow' => '주의', 'green' => '정상' }.freeze

    def frac(a, b)
      a && b && b.positive? ? "#{a}/#{b}" : nil
    end

    # 엑셀 한 줄
    def sheet_row(m)
      [m[:project].name, SIGNAL[m[:signal]], m[:reasons].join(', '), m[:start_on]&.to_s, m[:end_on]&.to_s, m[:elapsed] && "#{m[:elapsed]}%",
       m[:progress] && "#{m[:progress]}%", m[:gap], m[:overdue], m[:due_week], frac(m[:req_ok], m[:req_total]), frac(m[:prog_done], m[:prog_total]),
       m[:test_rate] && "#{m[:test_rate]}%", m[:defects], m[:risk_open], m[:risk_high], frac(m[:deliv_sub], m[:deliv_req]), m[:deliv_late], m[:cr_wait],
       m[:sr_open], m[:sr_over], m[:sr_rate] && "#{m[:sr_rate]}%", m[:audit_open], m[:staff_now], m[:mm_month]]
    end

    HEAD = %w(프로젝트 신호 이유 시작 종료 경과율 진척률 진척-경과(%p) 기한\ 지난\ 일감 이번\ 주\ 마감 요구사항\ 확정 프로그램\ 완료 테스트\ 합격률 미조치\ 결함
              열린\ 위험 위험\ 상 산출물\ 제출(필수) 산출물\ 마감\ 지남 변경요청\ 대기 SR\ 처리\ 중 SR\ 기한\ 지남 SR\ 준수율(이번\ 달) 감리\ 미확인 투입\ 인원 이번\ 달\ 계획\ M/M).freeze

    def sheet(rows, today = User.current.today)
      KrdsUi::Xlsx.build([{ name: "프로젝트 현황 #{today}", header: HEAD, rows: rows.map { |m| sheet_row(m) },
                            widths: [30, 8, 40, 12, 12, 8, 8, 10, 10, 10, 10, 10, 10, 10, 8, 8, 12, 12, 10, 10, 10, 12, 10, 8, 12] }])
    end
  end
end
