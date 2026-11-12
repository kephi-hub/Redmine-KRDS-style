# 요구사항 정의서 · 테스트 시나리오 ↔ 엑셀 표 (가져오기·내보내기 같은 양식)
# 가져오기: 머리줄 이름으로 칸을 찾음(띄어쓰기·괄호 무시), ID 가 같으면 값만 갱신, ID 가 없으면 새로 만들고 번호 자동
require 'csv'

module QaTrace
  module Sheet
    module_function

    REQ_FIELDS = {
      'code' => %w(요구사항id 요구사항번호 요구사항고유번호 고유번호 id 번호),
      'category' => %w(분류 구분 요구사항분류 요구사항구분 유형),
      'name' => %w(요구사항명 요구사항명칭 명칭 요구사항 제목),
      'description' => %w(상세 상세내용 요구사항내용 요구사항상세 내용 세부내용 정의 설명 요구사항정의),
      'source' => %w(출처 근거 산출근거 출처근거 요구사항출처),
      'priority' => %w(중요도 우선순위),
      'status' => %w(상태 진행상태),
      'parent' => %w(상위 상위id 상위요구사항 상위요구사항id),
      'menus' => %w(메뉴 화면 화면id 관련메뉴 관련화면 메뉴경로)
    }.freeze
    CASE_FIELDS = {
      'code' => %w(케이스id 테스트케이스id 테스트id id 번호 케이스번호),
      'kind' => %w(종류 구분 테스트구분 테스트종류 단계),
      'menu' => %w(화면id 메뉴 화면 화면명 메뉴명 메뉴경로),
      'requirements' => %w(요구사항id 요구사항 관련요구사항 요구사항번호),
      'name' => %w(케이스명 테스트케이스명 테스트명 시나리오명 시나리오 테스트항목 항목 제목),
      'precondition' => %w(사전조건 전제조건),
      'steps' => %w(절차 테스트절차 수행절차 테스트방법 수행방법 입력값),
      'expected' => %w(기대결과 예상결과 기대값 확인사항),
      'active' => %w(사용 사용여부)
    }.freeze
    PRIORITY = { 'high' => %w(high 상 높음 필수 h), 'normal' => %w(normal 중 보통 m), 'low' => %w(low 하 낮음 선택 l) }.freeze
    STATUS = { 'received' => %w(received 접수 신규 등록), 'confirmed' => %w(confirmed 확정 승인), 'changed' => %w(changed 변경 수정),
               'deleted' => %w(deleted 삭제 취소 철회) }.freeze
    KIND = { 'unit' => %w(unit 단위 단위테스트), 'integration' => %w(integration 통합 통합테스트), 'acceptance' => %w(acceptance 인수 사용자 인수테스트 사용자테스트 uat) }.freeze
    LABEL = {
      'priority' => { 'high' => '상', 'normal' => '중', 'low' => '하' },
      'status' => { 'received' => '접수', 'confirmed' => '확정', 'changed' => '변경', 'deleted' => '삭제' },
      'kind' => { 'unit' => '단위', 'integration' => '통합', 'acceptance' => '인수' },
      'result' => { 'none' => '미수행', 'pass' => '합격', 'fail' => '불합격', 'hold' => '보류', 'skip' => '제외' }
    }.freeze
    XLSX = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'.freeze

    def key(h)
      h.to_s.downcase.gsub(/[\s_·\-().\/]/, '')
    end

    def pick(map, value)
      v = key(value)
      return nil if v.empty?
      map.find { |_, names| names.include?(v) }&.first
    end

    # 파일 → 2차원 배열 (xlsx 또는 CSV, CSV 는 UTF-8/CP949)
    def read_file(file)
      raw = file.read
      return KrdsUi::XlsxReader.read(raw) if raw.start_with?('PK')
      text = raw.dup.force_encoding('UTF-8').delete_prefix("﻿")
      text = raw.dup.force_encoding('CP949').encode('UTF-8', invalid: :replace, undef: :replace) unless text.valid_encoding?
      CSV.parse(text)
    rescue CSV::MalformedCSVError
      nil
    end

    # 머리줄(칸 이름이 2개 이상 맞는 첫 줄)과 { 칸 => 열 번호 }
    def header(rows, fields)
      rows.each_with_index do |row, i|
        cols = {}
        row.each_with_index do |h, j|
          f = fields.find { |_, names| names.include?(key(h)) }&.first
          cols[f] ||= j if f
        end
        return [i, cols] if cols.size >= 2 && cols['name']
      end
      nil
    end

    def category(value, code)
      v = value.to_s.strip
      found = v.upcase[/\b(#{QaRequirement::CATEGORIES.join('|')})\b/, 1]
      found ||= QaRequirement::CATEGORY_NAMES.find { |_, n| key(n) == key(v) }&.first
      found || code.to_s.upcase[/\A([A-Z]{3})-/, 1].presence_in(QaRequirement::CATEGORIES)
    end

    # 메뉴 찾기: 화면 ID → 경로(가 > 나) → 이름(하나뿐일 때)
    def menu_finder(project)
      return nil unless project.module_enabled?(:menu_tree)
      all = MenuItem.where(project_id: project.id).to_a
      index = all.index_by(&:id)
      by_sid = all.select(&:screen_id).index_by { |m| m.screen_id.downcase }
      by_path = all.index_by { |m| key(m.path(index)) }
      by_name = all.group_by { |m| key(m.name) }
      lambda do |text|
        t = text.to_s.strip
        by_sid[t.downcase] || by_path[key(t)] || ((l = by_name[key(t)]) && l.size == 1 ? l.first : nil)
      end
    end

    # [줄 번호, 행] — ID 가 있는 줄을 먼저 (자동 번호가 같은 파일 안의 ID 와 겹치지 않게)
    def data_rows(rows, start, cols)
      list = rows[(start + 1)..].to_a.each_with_index.map { |row, n| [start + n + 2, row] }
      return list unless cols['code']
      coded, rest = list.partition { |_, row| row[cols['code']].to_s.strip.present? }
      coded + rest
    end

    def split(value)
      value.to_s.split(/[\n,;]+/).map(&:strip).reject(&:empty?)
    end

    # ---- 요구사항 ----

    def import_requirements(project, rows, user)
      head = header(rows, REQ_FIELDS)
      return nil unless head
      start, cols = head
      result = { created: 0, updated: 0, errors: [] }
      find_menu = menu_finder(project)
      parents = {}
      QaRequirement.transaction do
        data_rows(rows, start, cols).each do |line, row|
          val = ->(f) { cols[f] ? row[cols[f]].to_s.strip : nil }
          next if val.call('name').blank? && val.call('code').blank?
          code = val.call('code').presence&.upcase
          req = code && QaRequirement.where(project_id: project.id).where('UPPER(code) = ?', code).first
          # ID 가 없으면 같은 분류·같은 이름을 같은 요구사항으로 (다시 올려도 중복 안 생김)
          if code.nil? && val.call('name').present?
            cat0 = cols['category'] ? category(val.call('category'), nil) : nil
            same = QaRequirement.where(project_id: project.id, name: val.call('name'))
            req = (cat0 ? same.where(category: cat0) : same).first
          end
          is_new = req.nil?
          req ||= QaRequirement.new(project: project, code: code, author_id: user&.id)
          before = req.attributes.slice(*QaRequirement::TRACKED)
          cat = cols['category'] ? category(val.call('category'), code) : category(nil, code)
          req.category = cat if cat
          req.category ||= 'SFR' if is_new && cat.nil? && code.nil?
          req.name = val.call('name') if val.call('name').present?
          req.description = val.call('description') if cols['description']
          req.source = val.call('source') if cols['source']
          req.priority = pick(PRIORITY, val.call('priority')) || req.priority if cols['priority']
          req.status = pick(STATUS, val.call('status')) || req.status if cols['status']
          unless req.save
            result[:errors] << [line, "#{code || req.name}: #{req.errors.full_messages.join(', ')}"]
            next
          end
          extra = []
          if find_menu && cols['menus']
            names = split(val.call('menus'))
            found = names.filter_map { |t| find_menu.call(t) }
            (names.size - found.size).positive? && result[:errors] << [line, "#{req.code}: 메뉴를 찾지 못함 — #{names.reject { |t| find_menu.call(t) }.join(', ')}"]
            old = req.menu_items.to_a
            if found.map(&:id).uniq.sort != old.map(&:id).sort
              req.menu_item_ids = found.map(&:id).uniq
              extra << ['menus', old.map(&:name).join(', '), found.uniq.map(&:name).join(', ')]
            end
          end
          parents[req.id] = val.call('parent') if cols['parent']
          if is_new
            QaRequirementLog.create!(qa_requirement_id: req.id, user_id: user&.id, details: [['_import', nil, req.code]].to_json)
            result[:created] += 1
          else
            changed = req.log_changes(user, before, extra)
            result[:updated] += 1 if changed
          end
        end
        codes = QaRequirement.where(project_id: project.id).pluck(:code, :id).to_h { |c, i| [c.upcase, i] }
        parents.each do |rid, pcode|
          pid = pcode.present? ? codes[pcode.upcase] : nil
          QaRequirement.where(id: rid).update_all(parent_id: pid) if pid != rid
        end
      end
      result
    end

    def export_requirements(project, reqs, info)
      index = reqs.index_by(&:id)
      head = ['요구사항 ID', '분류', '요구사항명', '상세', '출처', '중요도', '상태', '상위 ID', '메뉴']
      rows = reqs.map do |r|
        i = info[r.id]
        [r.code, "#{QaRequirement::CATEGORY_NAMES[r.category]}(#{r.category})", r.name, r.description, r.source,
         LABEL['priority'][r.priority], LABEL['status'][r.status], index[r.parent_id]&.code,
         i[:menus].map { |m| m.screen_id || m.path(i[:menu_index]) }.join("\n")]
      end
      progs = info.values.any? { |i| i[:programs] }
      trace_head = ['요구사항 ID', '요구사항명', '상태', '메뉴'] + (progs ? ['프로그램', '프로그램 완료'] : []) + ['일감', '일감 완료', '테스트 케이스', '합격', '불합격', '미수행', '위험']
      trace = reqs.map do |r|
        i = info[r.id]
        [r.code, r.name, LABEL['status'][r.status], i[:menus].map { |m| m.path(i[:menu_index]) }.join("\n")] +
        (progs ? [(i[:programs] || []).map(&:code).join("\n"), (i[:programs] || []).any? ? "#{i[:programs_done]}/#{i[:programs].size}" : nil] : []) + [
         i[:issues].map { |x| "##{x.id}" }.join(', '), i[:issues].any? ? "#{i[:issues_closed]}/#{i[:issues].size}" : nil,
         i[:cases].map(&:code).join(', '), i[:pass], i[:fail], i[:untested], i[:risks].map { |k| RISK[k] }.join(', ')]
      end
      cats = QaRequirement::CATEGORIES.map { |c| [c, QaRequirement::CATEGORY_NAMES[c], reqs.count { |r| r.category == c && !r.deleted? }] }
      KrdsUi::Xlsx.build([
        { name: '요구사항 정의서', header: head, rows: rows, widths: [12, 14, 36, 60, 24, 8, 8, 12, 30] },
        { name: '요구사항 추적표', header: trace_head, rows: trace, widths: [12, 36, 8, 40] + (progs ? [20, 10] : []) + [20, 10, 30, 8, 8, 8, 24] },
        { name: '분류', header: %w(코드 분류 건수), rows: cats, widths: [8, 16, 8] }
      ])
    end

    RISK = { 'no_menu' => '메뉴 미연결', 'no_prog' => '프로그램 없음', 'no_test' => '테스트 없음', 'fail' => '불합격 있음', 'deleted_open' => '삭제됐는데 일감 진행 중' }.freeze

    # ---- 테스트 케이스 ----

    def import_cases(project, rows, user)
      head = header(rows, CASE_FIELDS)
      return nil unless head
      start, cols = head
      result = { created: 0, updated: 0, errors: [] }
      find_menu = menu_finder(project)
      reqs = QaRequirement.where(project_id: project.id).pluck(:code, :id).to_h { |c, i| [c.upcase, i] }
      QaTestCase.transaction do
        data_rows(rows, start, cols).each do |line, row|
          val = ->(f) { cols[f] ? row[cols[f]].to_s.strip : nil }
          next if val.call('name').blank? && val.call('code').blank?
          code = val.call('code').presence&.upcase
          tc = code && QaTestCase.where(project_id: project.id).where('UPPER(code) = ?', code).first
          # ID 가 없으면 같은 이름의 케이스를 같은 케이스로
          tc ||= QaTestCase.where(project_id: project.id, name: val.call('name')).first if code.nil? && val.call('name').present?
          is_new = tc.nil?
          tc ||= QaTestCase.new(project: project, code: code, author_id: user&.id)
          tc.name = val.call('name') if val.call('name').present?
          tc.kind = pick(KIND, val.call('kind')) || tc.kind if cols['kind']
          %w(precondition steps expected).each { |f| tc[f] = val.call(f) if cols[f] }
          tc.active = !%w(n no 미사용 x false 0).include?(val.call('active').to_s.downcase) if cols['active']
          if find_menu && cols['menu']
            text = val.call('menu')
            m = text.present? ? find_menu.call(text) : nil
            result[:errors] << [line, "#{code || tc.name}: 메뉴를 찾지 못함 — #{text}"] if text.present? && m.nil?
            tc.menu_item_id = m&.id if m || text.blank?
          end
          unless tc.save
            result[:errors] << [line, "#{code || tc.name}: #{tc.errors.full_messages.join(', ')}"]
            next
          end
          if cols['requirements']
            names = split(val.call('requirements')).map(&:upcase)
            missing = names.reject { |c| reqs[c] }
            result[:errors] << [line, "#{tc.code}: 요구사항을 찾지 못함 — #{missing.join(', ')}"] if missing.any?
            tc.qa_requirement_ids = names.filter_map { |c| reqs[c] }.uniq
          end
          is_new ? result[:created] += 1 : (result[:updated] += 1 if tc.saved_changes.except('updated_at').any? || cols['requirements'])
        end
      end
      result
    end

    def export_cases(project, cases, latest)
      index = project.module_enabled?(:menu_tree) ? MenuItem.where(project_id: project.id).index_by(&:id) : {}
      reqs = QaCaseRequirement.where(qa_test_case_id: cases.map(&:id)).joins(:qa_requirement).pluck(:qa_test_case_id, 'qa_requirements.code')
                              .group_by(&:first).transform_values { |l| l.map(&:last).sort }
      progs = program_codes(project, cases)
      head = ['케이스 ID', '종류', '화면 ID', '메뉴', '프로그램 ID', '요구사항 ID', '케이스명', '사전조건', '절차', '기대결과', '사용', '최근 결과']
      rows = cases.map do |c|
        m = index[c.menu_item_id]
        [c.code, LABEL['kind'][c.kind], m&.screen_id, m&.path(index), progs[c.pm_program_id], (reqs[c.id] || []).join(', '), c.name, c.precondition, c.steps,
         c.expected, c.active? ? 'Y' : 'N', LABEL['result'][latest[c.id]&.result || 'none']]
      end
      KrdsUi::Xlsx.build([{ name: '테스트 시나리오', header: head, rows: rows, widths: [12, 8, 14, 30, 16, 16, 36, 30, 50, 40, 6, 10] }])
    end

    # { 프로그램 id => 프로그램 ID } (프로그램 목록 모듈이 꺼져 있으면 빈 값)
    def program_codes(project, cases)
      return {} unless QaTrace::Trace.programs_on?(project)
      PmProgram.where(id: cases.map(&:pm_program_id).compact.uniq).pluck(:id, :code).to_h
    end

    # 테스트 결과서 (회차)
    def export_run(project, run, results)
      index = project.module_enabled?(:menu_tree) ? MenuItem.where(project_id: project.id).index_by(&:id) : {}
      progs = program_codes(project, results.map(&:qa_test_case))
      head = ['케이스 ID', '종류', '메뉴', '프로그램 ID', '케이스명', '사전조건', '절차', '기대결과', '결과', '수행자', '수행일시', '비고', '결함 일감']
      rows = results.map do |r|
        c = r.qa_test_case
        [c.code, LABEL['kind'][c.kind], index[c.menu_item_id]&.path(index), progs[c.pm_program_id], c.name, c.precondition, c.steps, c.expected,
         LABEL['result'][r.retest? ? 'fail' : r.result] + (r.retest? ? ' (재테스트 필요)' : ''), r.user&.name,
         r.tested_at && r.tested_at.in_time_zone(User.current.time_zone || Time.zone).strftime('%Y-%m-%d %H:%M'), r.note,
         r.issue_id ? "##{r.issue_id} #{r.issue&.status&.name}" : nil]
      end
      counts = results.group_by(&:result).transform_values(&:size)
      summary = [['회차', run.name], ['종류', run.kind.present? ? LABEL['kind'][run.kind] : '전체'],
                 ['기간', [run.start_on, run.end_on].compact.map(&:to_s).join(' ~ ')], ['대상', results.size]] +
                LABEL['result'].map { |k, v| [v, counts[k].to_i] } +
                [['진행률', "#{run.done_ratio}%"], ['결함 일감', results.count(&:issue_id)], ['비고', run.note]]
      KrdsUi::Xlsx.build([
        { name: '결과 요약', header: %w(항목 값), rows: summary, widths: [14, 50] },
        { name: '테스트 결과', header: head, rows: rows, widths: [12, 8, 30, 16, 36, 30, 50, 40, 10, 10, 16, 30, 16] }
      ])
    end
  end
end
