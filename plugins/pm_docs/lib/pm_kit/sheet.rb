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
