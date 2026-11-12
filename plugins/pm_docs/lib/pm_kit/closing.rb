# 준공(검수) 체크리스트 — 자동 항목은 다른 모듈 데이터로 그때그때 계산, 수동 항목은 확인 기록(PmClosingCheck)
# 결과: ok(충족) · ng(미충족) · na(해당 모듈을 쓰지 않음) · 수동 항목은 done 여부
# 모듈이 꺼져 있거나 보기 권한이 없으면 na — 화면에서 회색으로
module PmKit
  module Closing
    module_function

    GROUPS = [
      ['dev', '요구사항 · 개발 · 시험'],
      ['mgmt', '사업 관리'],
      ['staff', '인력 · 보안'],
      ['handover', '이관 · 검수 (직접 확인)']
    ].freeze

    # [키, 묶음, 항목] — 수동 항목 (m_ 로 시작)
    MANUAL = [
      ['m_training', 'handover', '사용자 · 운영자 교육 완료'],
      ['m_handover', 'handover', '운영 이관(인수인계) 완료'],
      ['m_source', 'handover', '최종 소스 · DB · 설치 파일 납품'],
      ['m_warranty', 'handover', '하자보수 계획 · 연락 체계 수립'],
      ['m_infra', 'handover', '서버 · VPN · DB 접근 권한 회수'],
      ['m_data', 'handover', '사업 자료 반납 · 파기 확인'],
      ['m_inspection', 'handover', '검수 요청 공문 발송'],
      ['m_report', 'handover', '완료보고서 제출']
    ].freeze
    MANUAL_KEYS = MANUAL.map(&:first).freeze

    def on?(project, user, mod, perm)
      project.module_enabled?(mod) && user.allowed_to?(perm, project)
    end

    def item(key, group, title, state, detail = nil, link = nil)
      { key: key, group: group, title: title, auto: true, state: state, detail: detail, link: link }
    end

    def ratio(ok, total)
      total.positive? && ok == total ? 'ok' : 'ng'
    end

    # 자동 항목 [{ key:, group:, title:, auto: true, state:, detail:, link: }]
    def auto_items(project, user = User.current, today = User.current.today)
      out = []
      p = project
      if defined?(QaRequirement) && on?(p, user, :qa_requirements, :view_qa_requirements)
        reqs = QaRequirement.where(project_id: p.id).alive.to_a
        okc = reqs.count { |r| %w(confirmed changed).include?(r.status) }
        out << item('req_confirmed', 'dev', '요구사항 모두 확정', reqs.empty? ? 'na' : ratio(okc, reqs.size), "확정 #{okc}/#{reqs.size}", [:project_qa_requirements_path, p])
        if defined?(QaTrace::Trace) && p.module_enabled?(:qa_tests) && reqs.any?
          info = QaTrace::Trace.build(p, reqs)
          passed = reqs.count { |r| info[r.id][:state] == 'pass' }
          out << item('req_tested', 'dev', '요구사항마다 테스트 합격', ratio(passed, reqs.size), "합격 #{passed}/#{reqs.size}", [:project_qa_requirements_trace_path, p])
        end
      end
      if on?(p, user, :programs, :view_programs)
        ps = PmProgram.where(project_id: p.id)
        done = ps.where(status: %w(done tested)).count
        out << item('programs_done', 'dev', '프로그램 모두 개발 완료', ps.none? ? 'na' : ratio(done, ps.count), "완료 #{done}/#{ps.count}", [:project_pm_programs_path, p])
      end
      if defined?(QaTestRun) && on?(p, user, :qa_tests, :view_qa_tests)
        run = QaTestRun.where(project_id: p.id).sorted.first
        if run
          res = run.qa_test_results.includes(:issue).to_a
          counted = res.reject { |r| r.result == 'skip' }
          pass = counted.count { |r| r.result == 'pass' }
          out << item('tests_pass', 'dev', "최근 테스트(#{run.name}) 모두 합격", counted.empty? ? 'ng' : ratio(pass, counted.size), "합격 #{pass}/#{counted.size}", [:project_qa_test_run_path, p, run])
          open = res.count { |r| r.issue && !r.issue.closed? }
          out << item('defects_closed', 'dev', '테스트 결함 모두 조치', open.zero? ? 'ok' : 'ng', "미조치 #{open}", [:project_qa_test_run_path, p, run])
        else
          out << item('tests_pass', 'dev', '테스트 수행', 'ng', '테스트 차수 없음', [:project_qa_test_cases_path, p])
        end
      end
      if defined?(MenuCapture) && on?(p, user, :menu_tree, :view_menu_captures)
        caps = MenuCapture.where(project_id: p.id, kind: 'pc').where.not(a11y_count: nil).order(:captured_at).to_a.index_by(&:menu_item_id).values
        if caps.any?
          bad = caps.count { |c| c.a11y_count.to_i.positive? }
          out << item('a11y_clean', 'dev', '웹 접근성 자동 점검 위반 없음', bad.zero? ? 'ok' : 'ng', "위반 화면 #{bad}/#{caps.size}", [:project_menu_captures_path, p, { filter: 'a11y' }])
        end
      end
      if on?(p, user, :issue_tracking, :view_issues)
        open = Issue.visible(user).where(project_id: p.id).open.count
        out << item('issues_closed', 'mgmt', '열린 일감 없음', open.zero? ? 'ok' : 'ng', "열린 일감 #{open}", [:project_issues_path, p])
      end
      if on?(p, user, :change_requests, :view_change_requests)
        wait = PmChangeRequest.where(project_id: p.id, status: %w(received analyzing)).count
        out << item('cr_closed', 'mgmt', '변경요청 모두 결정', wait.zero? ? 'ok' : 'ng', "대기 #{wait}", [:project_pm_change_requests_path, p])
      end
      if on?(p, user, :risks, :view_risks)
        open = PmRisk.where(project_id: p.id).to_a.count(&:open?)
        out << item('risks_closed', 'mgmt', '열린 이슈 · 위험 없음', open.zero? ? 'ok' : 'ng', "열림 #{open}", [:project_pm_risks_path, p])
      end
      if on?(p, user, :audits, :view_audits)
        au = PmAudit.where(project_id: p.id).to_a
        open = au.count(&:open?)
        out << item('audits_done', 'mgmt', '감리 지적사항 모두 조치 확인', open.zero? ? 'ok' : 'ng', "미확인 #{open}/#{au.size}", [:project_pm_audits_path, p])
      end
      if on?(p, user, :sec_scans, :view_sec_scans)
        open = PmSecItem.where(project_id: p.id, status: 'open').count
        out << item('sec_fixed', 'mgmt', '보안약점 모두 조치', open.zero? ? 'ok' : 'ng', "미조치 #{open}", [:project_pm_sec_scans_path, p])
      end
      if on?(p, user, :deliverables, :view_deliverables)
        req = PmDeliverable.where(project_id: p.id, required: true).to_a
        sub = req.count { |d| d.status == 'submitted' }
        out << item('deliv_submitted', 'mgmt', '필수 산출물 모두 제출', req.empty? ? 'na' : ratio(sub, req.size), "제출 #{sub}/#{req.size}", [:project_pm_deliverables_path, p])
      end
      if on?(p, user, :staff, :view_staff)
        st = PmStaff.where(project_id: p.id).to_a
        if st.any?
          ended = st.count { |s| s.end_on && s.end_on <= today }
          out << item('staff_out', 'staff', '투입 인력 철수(종료일 지남)', ratio(ended, st.size), "철수 #{ended}/#{st.size}", [:project_pm_staffs_path, p])
          acc = st.select { |s| s.accounts.present? }
          rev = acc.count(&:revoked_on)
          out << item('staff_revoked', 'staff', '인력 계정 모두 회수', acc.empty? ? 'na' : ratio(rev, acc.size), "회수 #{rev}/#{acc.size}", [:project_pm_staffs_path, p])
          pl = st.count(&:pledge_on)
          out << item('pledge', 'staff', '보안 서약서 모두 제출', ratio(pl, st.size), "제출 #{pl}/#{st.size}", [:project_pm_staffs_path, p])
        end
      end
      out
    end

    def manual_items(project)
      checks = PmClosingCheck.where(project_id: project.id).includes(:user).to_a.index_by(&:key)
      MANUAL.map do |key, group, title|
        c = checks[key]
        { key: key, group: group, title: title, auto: false, state: c&.done ? 'ok' : 'ng', detail: c&.note, check: c }
      end
    end

    def items(project, user = User.current)
      auto_items(project, user) + manual_items(project)
    end

    # 준비율: na 를 뺀 항목 중 충족 비율
    def progress(items)
      counted = items.reject { |i| i[:state] == 'na' }
      okc = counted.count { |i| i[:state] == 'ok' }
      [okc, counted.size, counted.empty? ? 0 : (okc * 100 / counted.size)]
    end

    STATE = { 'ok' => '충족', 'ng' => '미충족', 'na' => '해당 없음' }.freeze

    # 사업 요약 (완료보고서 초안) — [항목, 값]
    def summary(project, user = User.current, today = User.current.today)
      m = PmKit::Portfolio.metrics(project, user, today)
      rows = [['사업명', project.name], ['기준일', today.to_s],
              ['사업 기간(일감 기준)', [m[:start_on], m[:end_on]].compact.join(' ~ ')], ['일감 진척률', m[:progress] && "#{m[:progress]}%"]]
      rows << ['요구사항 확정', PmKit::Portfolio.frac(m[:req_ok], m[:req_total])] if m.key?(:req_total)
      rows << ['프로그램 완료', PmKit::Portfolio.frac(m[:prog_done], m[:prog_total])] if m.key?(:prog_total)
      rows << ['최근 테스트 합격률', m[:test_rate] && "#{m[:test_rate]}%"] if m.key?(:test_rate)
      rows << ['미조치 결함', m[:defects]] if m.key?(:defects)
      rows << ['필수 산출물 제출', PmKit::Portfolio.frac(m[:deliv_sub], m[:deliv_req])] if m.key?(:deliv_req)
      rows << ['감리 미확인', m[:audit_open]] if m.key?(:audit_open)
      rows << ['열린 위험', m[:risk_open]] if m.key?(:risk_open)
      if project.module_enabled?(:staff) && user.allowed_to?(:view_staff, project)
        st = PmStaff.where(project_id: project.id).to_a
        if st.any?
          from = st.filter_map(&:start_on).min || today
          to = [st.filter_map(&:end_on).max, today].compact.max
          rows << ['투입 인력', "#{st.size}명"]
          rows << ['계획 M/M', st.sum { |s| s.plan_mm(from, to) }.round(2)]
          rows << ['실적 M/M(소요 시간)', st.sum { |s| s.actual_mm(from, to).to_f }.round(2)]
        end
      end
      if project.module_enabled?(:baselines) && user.allowed_to?(:view_baselines, project) && (b = PmBaseline.where(project_id: project.id).order(:taken_on, :id).first)
        cmp = b.compare(user)[:summary]
        rows << ["최초 기준선(#{b.name}) 대비 종료일", cmp[:end_shift].nil? ? '-' : "#{cmp[:base_end]} → #{cmp[:now_end]} (#{cmp[:end_shift].positive? ? '+' : ''}#{cmp[:end_shift]}일)"]
      end
      rows
    end

    def sheet(project, user = User.current)
      list = items(project, user)
      groups = GROUPS.to_h
      rows = list.map do |i|
        c = i[:check]
        [groups[i[:group]], i[:title], i[:auto] ? '자동' : '직접 확인', i[:auto] ? STATE[i[:state]] : (i[:state] == 'ok' ? '완료' : '미완료'),
         i[:auto] ? i[:detail] : nil, c&.user&.name, c&.checked_at&.localtime&.strftime('%Y-%m-%d'), i[:auto] ? nil : c&.note]
      end
      okc, total, pct = progress(list)
      KrdsUi::Xlsx.build([
        { name: '준공 체크리스트', header: %w(구분 항목 방법 결과 내용 확인자 확인일 비고), rows: rows, widths: [22, 34, 10, 10, 20, 12, 12, 40] },
        { name: '사업 요약', header: %w(항목 값), rows: summary(project, user) + [['준공 준비율', "#{okc}/#{total} (#{pct}%)"]], widths: [30, 50] }
      ])
    end
  end
end
