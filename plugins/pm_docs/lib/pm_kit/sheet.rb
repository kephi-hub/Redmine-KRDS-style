# 엑셀 — 변경요청 목록, 프로그램 목록, 이슈·위험 관리대장, 회의록 모음, 산출물 목록
module PmKit
  module Sheet
    module_function

    XLSX = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'.freeze
    LABEL = {
      'phase' => { 'start' => '착수', 'analysis' => '분석', 'design' => '설계', 'build' => '구현', 'test' => '시험', 'transition' => '이행', 'close' => '종료' },
      'dstatus' => { 'none' => '미작성', 'writing' => '작성 중', 'review' => '검토', 'approved' => '승인', 'submitted' => '제출' },
      'crstatus' => { 'received' => '접수', 'analyzing' => '영향 분석', 'approved' => '승인', 'rejected' => '반려', 'done' => '반영 완료' },
      'priority' => { 'high' => '상', 'normal' => '중', 'low' => '하' },
      'aphase' => { 'analysis' => '요구정의 단계', 'design' => '설계 단계', 'close' => '종료 단계', 'etc' => '기타' },
      'aarea' => { 'pm' => '사업관리', 'app' => '응용시스템', 'db' => '데이터베이스', 'arch' => '시스템 구조', 'sec' => '보안', 'test' => '테스트', 'etc' => '기타' },
      'akind' => { 'correct' => '시정', 'advise' => '권고', 'note' => '참고' },
      'astatus' => { 'received' => '접수', 'planned' => '조치 계획', 'acting' => '조치 중', 'done' => '조치 완료', 'verified' => '확인 완료' },
      'srole' => { 'pm' => 'PM', 'pl' => 'PL', 'dev' => '개발', 'design' => '디자인', 'pub' => '퍼블리싱', 'dba' => 'DBA', 'qa' => 'QA·테스트', 'etc' => '기타' },
      'sgrade' => { 'special' => '특급', 'high' => '고급', 'mid' => '중급', 'low' => '초급' },
      'seclevel' => { 'high' => '상', 'mid' => '중', 'low' => '하' },
      'secstatus' => { 'open' => '미조치', 'fixed' => '조치 완료', 'except' => '예외' },
      'recheck' => { 'pass' => '재진단 통과', 'fail' => '재진단 남음' },
      'paction' => { 'select' => '조회', 'insert' => '등록', 'update' => '수정', 'delete' => '삭제', 'download' => '다운로드', 'upload' => '업로드', 'print' => '출력', 'approve' => '승인', 'etc' => '기타' },
      'pkind' => { 'screen' => '화면', 'popup' => '팝업', 'batch' => '배치', 'api' => 'API', 'common' => '공통', 'report' => '리포트' },
      'pstatus' => { 'todo' => '미착수', 'dev' => '개발 중', 'done' => '개발 완료', 'tested' => '단위테스트 완료' },
      'rkind' => { 'risk' => '위험', 'issue' => '이슈' },
      'rstatus' => { 'open' => '식별', 'action' => '대응 중', 'watch' => '관찰', 'closed' => '종료', 'occurred' => '발생' },
      'level' => { 'high' => '상', 'mid' => '중', 'low' => '하' },
      'phl' => { 1 => '하', 2 => '중', 3 => '상' }
    }.freeze

    def fmt(t)
      t && t.in_time_zone(ActiveSupport::TimeZone['Asia/Seoul']).strftime('%Y-%m-%d %H:%M')
    end

    def change_requests(list)
      rows = list.map do |c|
        [c.code, c.title, LABEL['priority'][c.priority], LABEL['crstatus'][c.status], c.requester, c.requested_on&.to_s, c.description, c.reason,
         c.requirements.map(&:code).join(', '), c.menus.map(&:name).join(', '), c.interfaces.map(&:code).join(', '), c.tables, c.effort&.to_f, c.schedule_impact,
         c.impact, c.decided_by&.name, c.decided_on&.to_s, c.decision_note, c.issues.map { |i| "##{i.id}" }.join(', ')]
      end
      KrdsUi::Xlsx.build([{ name: '변경요청 관리대장', header: %w(CR\ ID 제목 우선순위 상태 요청자 요청일 요청\ 내용 사유 관련\ 요구사항 관련\ 메뉴 관련\ 인터페이스 관련\ 테이블 예상\ 공수(인일) 일정\ 영향 영향\ 분석 결정자 결정일 결정\ 의견 반영\ 일감),
                            rows: rows, widths: [10, 30, 8, 10, 12, 12, 40, 30, 20, 24, 16, 20, 10, 24, 30, 10, 12, 30, 16] }])
    end

    def programs(list, index = {})
      rows = list.map do |p|
        m = index[p.menu_item_id]
        [p.code, p.name, LABEL['pkind'][p.kind], p.action_list.map { |a| LABEL['paction'][a] }.join(', '), m&.screen_id, m && m.path(index), p.paths.join("\n"), p.developer&.name, LABEL['pstatus'][p.status],
         p.planned_on&.to_s, p.done_on&.to_s, p.note]
      end
      KrdsUi::Xlsx.build([{ name: '프로그램 목록', header: %w(프로그램\ ID 프로그램명 유형 처리\ 구분 화면\ ID 메뉴 소스\ 경로 개발자 상태 계획일 완료일 비고), rows: rows,
                            widths: [18, 30, 8, 16, 14, 30, 50, 10, 14, 12, 12, 24] }])
    end

    # 주간·월간 보고서 (PmKit::Report.build 결과) — notes: 화면에서 적은 주요 이슈·건의
    def report(project, data, notes = nil)
      ih = %w(번호 유형 제목 상태 담당 진척 시작일 완료\ 기한)
      sheets = [{ name: '요약', header: %w(항목 값), rows: [['프로젝트', project.name]] + data[:summary] + (notes.present? ? [['주요 이슈·건의', notes]] : []), widths: [20, 80] }]
      sheets << { name: '버전 진척', header: %w(버전 완료\ 예정일 진척률 일감\ 수), rows: data[:versions], widths: [24, 14, 10, 10] } if data[:versions]
      sheets << { name: '기간 실적', header: ih + %w(구분), rows: data[:done], widths: [8, 10, 50, 10, 12, 8, 12, 12, 8] }
      sheets << { name: '다음 기간 계획', header: ih, rows: data[:plan], widths: [8, 10, 50, 10, 12, 8, 12, 12] }
      sheets << { name: '기한 지남', header: ih, rows: data[:late], widths: [8, 10, 50, 10, 12, 8, 12, 12] }
      sheets << { name: '이슈·위험', header: %w(ID 구분 제목 등급 상태 담당 기한 대응\ 계획), rows: data[:risks], widths: [8, 8, 40, 8, 10, 12, 12, 50] } if data[:risks]
      sheets << { name: '변경요청', header: %w(ID 제목 상태 요청일 결정일 공수(인일) 일정\ 영향), rows: data[:crs], widths: [10, 40, 10, 12, 12, 10, 30] } if data[:crs]
      sheets << { name: '산출물', header: %w(ID 산출물 상태 담당 마감일 제출일 구분), rows: data[:deliverables], widths: [8, 36, 10, 12, 12, 12, 14] } if data[:deliverables]
      sheets << { name: '테스트·결함', header: %w(항목 값), rows: data[:tests], widths: [20, 10] } if data[:tests]
      if data[:sr]
        sheets << { name: 'SR·SLA', header: %w(항목 값), rows: data[:sr][:summary], widths: [20, 12] }
        sheets << { name: 'SR 목록', header: ih + %w(긴급도 SLA), rows: data[:sr][:rows], widths: [8, 8, 50, 10, 12, 8, 12, 12, 8, 8] }
      end
      sheets << { name: '투입 인력', header: %w(이름 역할 소속 계획\ M/M 실적\ M/M), rows: data[:staff], widths: [12, 10, 16, 10, 10] } if data[:staff]
      sheets << { name: '감리 지적', header: %w(ID 회차 지적사항 상태 담당 기한 비고), rows: data[:audits], widths: [8, 24, 40, 10, 12, 12, 10] } if data[:audits]
      KrdsUi::Xlsx.build(sheets)
    end

    # 감리 시정조치 계획서 · 결과 보고서
    def audits(list)
      d = ->(x) { x&.to_s }
      plan = list.map { |a| [a.code, a.pm_audit_round&.name, LABEL['aarea'][a.area], LABEL['akind'][a.kind], a.title, a.content, a.basis, a.plan, a.owner&.name, d.(a.due_on), LABEL['astatus'][a.status]] }
      result = list.map { |a| [a.code, a.pm_audit_round&.name, LABEL['akind'][a.kind], a.title, a.plan, a.result, LABEL['astatus'][a.status], d.(a.done_on), d.(a.verified_on), a.issue_id ? "##{a.issue_id}" : nil, a.pm_deliverable&.code] }
      by = list.group_by(&:pm_audit_round).map do |r, l|
        [r&.name || '회차 없음', r ? LABEL['aphase'][r.phase] : nil, l.size, l.count { |a| a.status == 'verified' }, l.count { |a| a.status == 'done' }, l.count(&:open?), l.count(&:late?)]
      end
      KrdsUi::Xlsx.build([
        { name: '요약', header: %w(회차 단계 지적 확인\ 완료 조치\ 완료 미확인 기한\ 지남), rows: by, widths: [30, 14, 8, 10, 10, 8, 10] },
        { name: '시정조치 계획', header: %w(ID 회차 영역 구분 지적사항 내용 근거 조치\ 계획 담당 기한 상태), rows: plan, widths: [10, 24, 12, 8, 36, 50, 20, 50, 10, 12, 10] },
        { name: '시정조치 결과', header: %w(ID 회차 구분 지적사항 조치\ 계획 조치\ 결과 상태 조치일 확인일 일감 산출물), rows: result, widths: [10, 24, 8, 36, 40, 50, 10, 12, 12, 10, 10] }
      ])
    end

    # 투입인력 현황 — 인력 목록 + 월별 계획·실적 M/M
    def staff(list, from, to)
      months = []
      m = from.beginning_of_month
      while m <= to
        months << m
        m = m.next_month
      end
      people = list.map do |x|
        [x.name, x.company, LABEL['srole'][x.role], LABEL['sgrade'][x.grade], x.start_on&.to_s, x.end_on&.to_s, x.rate, x.plan_mm(from, to), x.actual_mm(from, to),
         x.pledge_on&.to_s, x.accounts, x.revoked_on&.to_s, x.replace_of&.name, x.replace_reason, x.replace_approved_on&.to_s, x.note]
      end
      plan = list.map { |x| [x.name, LABEL['srole'][x.role]] + months.map { |mm| x.plan_mm(mm, mm.end_of_month) } + [x.plan_mm(from, to)] }
      act = list.select(&:user_id).map { |x| [x.name, LABEL['srole'][x.role]] + months.map { |mm| x.actual_mm(mm, mm.end_of_month) } + [x.actual_mm(from, to)] }
      mh = months.map { |mm| mm.strftime('%Y-%m') }
      KrdsUi::Xlsx.build([
        { name: '투입 인력', header: %w(이름 소속 역할 등급 투입\ 시작 투입\ 종료 투입률(%) 계획\ M/M 실적\ M/M 보안서약서 계정\ 발급 회수일 교체\ 전 교체\ 사유 교체\ 승인일 비고),
          rows: people, widths: [12, 16, 10, 8, 12, 12, 10, 10, 10, 12, 30, 12, 12, 24, 12, 24] },
        { name: '월별 계획 MM', header: %w(이름 역할) + mh + %w(합계), rows: plan, widths: [12, 10] + months.map { 9 } + [9] },
        { name: '월별 실적 MM', header: %w(이름 역할) + mh + %w(합계), rows: act, widths: [12, 10] + months.map { 9 } + [9] },
        { name: '월별 계획 대 실적', header: %w(월 계획\ M/M 실적\ M/M 차이 실적률(%)),
          rows: staff_months(list, from, to).map { |r| [r[:month].strftime('%Y-%m'), r[:plan], r[:actual], r[:diff], r[:rate]] }, widths: [10, 10, 10, 10, 10] }
      ])
    end

    # 월별 계획 대 실적 (실적은 Redmine 사용자를 연결한 인력만) — [{ month:, plan:, actual:, diff:, rate: }]
    def staff_months(list, from, to)
      rows = []
      m = from.beginning_of_month
      while m <= to
        e = m.end_of_month
        plan = list.sum { |x| x.plan_mm(m, e) }.round(2)
        actual = list.sum { |x| x.actual_mm(m, e).to_f }.round(2)
        rows << { month: m, plan: plan, actual: actual, diff: (actual - plan).round(2), rate: plan.positive? ? (actual * 100 / plan).round : nil }
        m = m.next_month
      end
      rows
    end

    # 일정 기준선 비교 — 요약 · 일감별
    def baseline(b, cmp)
      s = cmp[:summary]
      kind = { 'kept' => '', 'added' => '기준 뒤 추가', 'removed' => '삭제됨' }
      info = [['기준선', b.name], ['저장일', b.taken_on.to_s], ['저장자', b.author&.name], ['메모', b.note], ['기준 일감 수', b.issue_count],
              ['기준 종료일', s[:base_end]&.to_s], ['지금 종료일', s[:now_end]&.to_s], ['종료일 변동(일)', s[:end_shift]],
              ['완료 기한이 늦어진 일감', s[:late]], ['앞당겨진 일감', s[:early]], ['추가된 일감', s[:added]], ['삭제된 일감', s[:removed]], ['가장 많이 늦어진 일수', s[:max_late]]]
      rows = cmp[:rows].map do |r|
        i = r[:issue]; x = r[:base]
        [r[:id], i&.tracker&.name, r[:subject], i&.status&.name, i&.assigned_to&.name, x&.start_date&.to_s, x&.due_date&.to_s, i&.start_date&.to_s, i&.due_date&.to_s,
         r[:start_shift], r[:due_shift], x&.done_ratio, i&.done_ratio, kind[r[:kind]]]
      end
      KrdsUi::Xlsx.build([
        { name: '요약', header: %w(항목 값), rows: info, widths: [24, 40] },
        { name: '일감별 비교', header: %w(번호 유형 제목 상태 담당자 기준\ 시작 기준\ 완료 지금\ 시작 지금\ 완료 시작\ 변동(일) 완료\ 변동(일) 기준\ 진척(%) 지금\ 진척(%) 구분),
          rows: rows, widths: [8, 10, 40, 8, 10, 12, 12, 12, 12, 10, 10, 10, 10, 12] }
      ])
    end

    # 보안약점 진단 결과 · 조치 내역 (회차)
    def sec_scan(scan, items)
      rows = items.map do |i|
        [i.kind, LABEL['seclevel'][i.level], i.file_path, i.line, i.description, LABEL['secstatus'][i.status], i.reason, i.fixer&.name, i.fixed_on&.to_s,
         i.recheck.present? ? LABEL['recheck'][i.recheck] : nil, i.pm_program&.code]
      end
      by = items.group_by(&:kind).map { |k, l| [k, l.size, l.count { |i| i.level == 'high' }, l.count { |i| i.status == 'fixed' }, l.count { |i| i.status == 'except' }, l.count { |i| i.status == 'open' }] }
      info = [['회차', scan.name], ['도구', scan.tool], ['진단일', scan.scanned_on&.to_s], ['대상 리비전', scan.revision], ['진단자', scan.scanner],
              ['전체', items.size], ['미조치', items.count { |i| i.status == 'open' }], ['조치 완료', items.count { |i| i.status == 'fixed' }], ['예외', items.count { |i| i.status == 'except' }]]
      KrdsUi::Xlsx.build([
        { name: '요약', header: %w(항목 값), rows: info, widths: [14, 40] },
        { name: '유형별', header: %w(보안약점\ 유형 전체 위험도\ 상 조치\ 완료 예외 미조치), rows: by, widths: [36, 8, 10, 10, 8, 8] },
        { name: '진단 항목', header: %w(보안약점\ 유형 위험도 파일 라인 설명 상태 예외·조치\ 사유 조치자 조치일 재진단 프로그램), rows: rows, widths: [30, 8, 50, 8, 50, 10, 36, 10, 12, 12, 16] }
      ])
    end

    def risks(list)
      rows = list.map do |r|
        [r.code, LABEL['rkind'][r.kind], r.title, r.description, LABEL['phl'][r.probability], LABEL['phl'][r.impact], LABEL['level'][r.level], LABEL['rstatus'][r.status],
         r.owner&.name, r.plan, r.due_on&.to_s, r.raised_on&.to_s, r.closed_on&.to_s, r.issue_id ? "##{r.issue_id}" : nil]
      end
      KrdsUi::Xlsx.build([{ name: '이슈·위험 관리대장', header: %w(ID 구분 제목 내용 가능성 영향 등급 상태 담당 대응\ 계획 기한 식별일 종료일 일감), rows: rows,
                            widths: [8, 6, 30, 40, 8, 8, 6, 8, 10, 40, 12, 12, 12, 8] }])
    end

    def meetings(list)
      rows = list.map do |m|
        acts = m.action_list.map { |a| "#{a['title']}#{" (#{User.find_by(id: a['assignee_id'])&.name})" if a['assignee_id'].present?}#{" ~#{a['due_on']}" if a['due_on'].present?}#{" ##{a['issue_id']}" if a['issue_id']}" }
        [fmt(m.held_at), m.title, m.place, m.attendees, m.agenda, m.notes, m.decision_list.join("\n"), acts.join("\n")]
      end
      KrdsUi::Xlsx.build([{ name: '회의록', header: %w(일시 제목 장소 참석자 안건 내용 결정\ 사항 후속\ 조치), rows: rows, widths: [17, 30, 14, 24, 30, 50, 40, 40] }])
    end

    def deliverables(list)
      rows = list.map do |d|
        a = d.latest_attachment
        ap = d.last_approval
        [LABEL['phase'][d.phase], d.code, d.name, d.required ? 'Y' : 'N', LABEL['dstatus'][d.status], d.version, d.owner&.name, d.due_on&.to_s, d.submitted_on&.to_s,
         ap&.user&.name, ap && fmt(ap.created_at), d.auto_kind ? PmKit::AutoDocs::KINDS[d.auto_kind]&.dig(:label) : nil, a&.filename, d.attachments.size, d.note]
      end
      hist = list.flat_map do |d|
        d.pm_deliverable_reviews.map do |r|
          [d.code, d.name, fmt(r.created_at), r.user&.name, ACT[r.action], r.status_from && LABEL['dstatus'][r.status_from], r.status_to && LABEL['dstatus'][r.status_to], r.version, r.note]
        end
      end
      KrdsUi::Xlsx.build([
        { name: '산출물 목록', header: %w(단계 ID 산출물 필수 상태 버전 담당 마감일 제출일 승인자 승인일시 자동\ 생성 최신\ 파일 파일\ 수 비고), rows: rows,
          widths: [8, 10, 30, 6, 8, 8, 10, 12, 12, 10, 17, 24, 30, 8, 30] },
        { name: '검토·승인 이력', header: %w(ID 산출물 일시 처리자 처리 이전\ 상태 바뀐\ 상태 버전 의견), rows: hist, widths: [10, 30, 17, 10, 10, 10, 10, 8, 40] }
      ])
    end

    ACT = { 'request' => '검토 요청', 'approve' => '승인', 'reject' => '반려', 'submit' => '제출', 'reopen' => '되돌림', 'edit' => '수정', 'upload' => '파일 올림' }.freeze

    # WBS: 일감 트리(상위 → 하위) 번호 1, 1.1, 1.1.1 …
    def wbs(project)
      issues = Issue.where(project_id: project.id).includes(:tracker, :status, :assigned_to, :fixed_version).to_a
      by_parent = issues.group_by(&:parent_id)
      ids = issues.map(&:id).to_set
      roots = issues.select { |i| i.parent_id.nil? || !ids.include?(i.parent_id) }
      order = ->(l) { l.sort_by { |i| [i.start_date || Date.new(9999), i.id] } }
      rows = []
      walk = lambda do |list, prefix|
        order.call(list).each_with_index do |i, n|
          no = prefix ? "#{prefix}.#{n + 1}" : (n + 1).to_s
          depth = no.count('.')
          rows << [no, "#{'  ' * depth}#{i.subject}", i.tracker&.name, i.assigned_to&.name, i.start_date&.to_s, i.due_date&.to_s, i.done_ratio, i.status&.name,
                   i.fixed_version&.name, i.estimated_hours, "##{i.id}"]
          walk.call(by_parent[i.id] || [], no)
        end
      end
      walk.call(roots, nil)
      versions = project.shared_versions.sort.map { |v| [v.name, v.effective_date&.to_s, v.status, v.completed_percent.to_i, v.description] }
      KrdsUi::Xlsx.build([
        { name: 'WBS', header: %w(WBS 작업 유형 담당 시작일 완료\ 예정일 진척(%) 상태 버전 예상(시간) 일감), rows: rows, widths: [10, 50, 10, 10, 12, 12, 8, 10, 14, 10, 8] },
        { name: '마일스톤(버전)', header: %w(버전 완료일 상태 진척(%) 설명), rows: versions, widths: [20, 12, 8, 8, 40] }
      ])
    end

    # 결함 조치 내역: "결함" 트래커 일감 + 테스트 불합격으로 만든 일감, 원인 회차·케이스와 재테스트 결과
    def defects(project)
      from_tests = defined?(QaTestResult) ? QaTestResult.joins(:qa_test_run).where(qa_test_runs: { project_id: project.id }).where.not(issue_id: nil).includes(:qa_test_run, :qa_test_case).to_a : []
      by_issue = from_tests.group_by(&:issue_id)
      ids = Issue.where(project_id: project.id).joins(:tracker).where(trackers: { name: '결함' }).pluck(:id) | by_issue.keys
      latest = defined?(QaTrace) ? QaTrace::Trace.latest_results(project) : {}
      rows = Issue.where(id: ids).includes(:status, :assigned_to, :tracker).order(:id).map do |i|
        src = by_issue[i.id]&.first
        retest = src && latest[src.qa_test_case_id]
        [i.id, i.subject, i.tracker&.name, src ? "#{src.qa_test_run.name} · #{src.qa_test_case.code}" : nil, i.status&.name, i.assigned_to&.name,
         i.created_on && fmt(i.created_on), i.closed_on && fmt(i.closed_on), retest ? LABEL_RESULT[retest.result] : nil, i.done_ratio]
      end
      open = rows.count { |r| Issue.find_by(id: r[0])&.closed? == false }
      summary = [['결함 수', rows.size], ['조치 완료', rows.size - open], ['미조치', open]]
      KrdsUi::Xlsx.build([
        { name: '결함 조치 내역', header: %w(일감 제목 유형 발견(회차·케이스) 상태 담당 등록 조치\ 완료 재테스트 진척(%)), rows: rows, widths: [8, 40, 8, 28, 10, 10, 17, 17, 10, 8] },
        { name: '요약', header: %w(항목 값), rows: summary, widths: [14, 10] }
      ])
    end

    LABEL_RESULT = { 'none' => '미수행', 'pass' => '합격', 'fail' => '불합격', 'hold' => '보류', 'skip' => '제외' }.freeze
  end
end
