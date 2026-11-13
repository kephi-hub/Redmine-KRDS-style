# 프로그램 목록 엑셀 가져오기 — 머리줄 이름으로 칸 찾기, 프로그램 ID 가 같으면 갱신
module PmKit
  module Importer
    module_function

    FIELDS = {
      'code' => %w(프로그램id 프로그램아이디 프로그램번호 id), 'name' => %w(프로그램명 이름 프로그램이름), 'kind' => %w(유형 구분 종류), 'actions' => %w(처리구분 처리 기능구분 기능 crud),
      'menu' => %w(화면id 메뉴 화면 메뉴경로), 'paths' => %w(소스경로 소스 경로 파일), 'developer' => %w(개발자 담당 담당자),
      'status' => %w(상태 진척), 'planned_on' => %w(계획일 완료예정일), 'done_on' => %w(완료일), 'note' => %w(비고)
    }.freeze

    def key(h)
      h.to_s.downcase.gsub(/[\s_·\-().\/]/, '')
    end

    # 업로드한 엑셀(xlsx) 또는 CSV(UTF-8·CP949) → 2차원 배열
    def read_file(file)
      raw = file.read
      return KrdsUi::XlsxReader.read(raw) if raw.start_with?('PK')
      text = raw.dup.force_encoding('UTF-8').delete_prefix("\uFEFF")
      text = raw.dup.force_encoding('CP949').encode('UTF-8', invalid: :replace, undef: :replace) unless text.valid_encoding?
      CSV.parse(text)
    rescue CSV::MalformedCSVError
      nil
    end

    def invert(group)
      PmKit::Sheet::LABEL[group].to_h { |k, v| [key(v), k] }
    end

    # "조회, 등록" · "S/I/U/D" · "select" 모두 받음
    def action_codes(text)
      labels = invert('paction')
      letters = PmProgram::SUFFIX.invert
      text.to_s.split(%r{[,·/\s]+}).filter_map { |t| labels[key(t)] || letters[t.upcase] || PmProgram::ACTIONS.find { |a| a == t.downcase } }.uniq
    end

    def programs(project, rows)
      start = rows.index { |r| r.count { |h| FIELDS.values.flatten.include?(key(h)) } >= 2 }
      return nil unless start
      cols = {}
      rows[start].each_with_index { |h, i| (f = FIELDS.find { |_, n| n.include?(key(h)) }&.first) && cols[f] ||= i }
      return nil unless cols['code'] && cols['name']
      menus = defined?(MenuItem) && project.module_enabled?(:menu_tree) ? MenuItem.where(project_id: project.id).to_a : []
      index = menus.index_by(&:id)
      by_sid = menus.select(&:screen_id).index_by { |m| m.screen_id.downcase }
      # 사이트 표시가 있는 경로 · 없는 경로 모두로 찾음
      by_path = menus.index_by { |m| key(m.path(index, site: false)) }.merge(menus.index_by { |m| key(m.path(index)) })
      users = project.users.to_a
      kinds = invert('pkind')
      statuses = invert('pstatus')
      result = { created: 0, updated: 0, errors: [] }
      rows[(start + 1)..].to_a.each_with_index do |row, n|
        val = ->(f) { cols[f] ? row[cols[f]].to_s.strip : nil }
        code = val.call('code')
        next if code.blank?
        p = PmProgram.where(project_id: project.id).where('UPPER(code) = ?', code.upcase).first
        is_new = p.nil?
        p ||= PmProgram.new(project: project, code: code, status: 'todo', kind: 'screen')
        p.name = val.call('name') if val.call('name').present?
        p.kind = kinds[key(val.call('kind'))] || PmProgram::KINDS.find { |k| k == val.call('kind') } || p.kind if cols['kind']
        p.status = statuses[key(val.call('status'))] || p.status if cols['status']
        p.action_list = action_codes(val.call('actions')) if cols['actions']
        if cols['menu'] && val.call('menu').present?
          t = val.call('menu')
          m = by_sid[t.downcase] || by_path[key(t)]
          m ? p.menu_item_id = m.id : result[:errors] << [start + n + 2, "#{code}: 메뉴를 찾지 못함 — #{t}"]
        end
        p.source_paths = val.call('paths') if cols['paths']
        if cols['developer'] && val.call('developer').present?
          d = val.call('developer')
          u = users.find { |x| x.login == d || x.name == d || "#{x.lastname}#{x.firstname}" == d.delete(' ') }
          u ? p.developer_id = u.id : result[:errors] << [start + n + 2, "#{code}: 개발자를 찾지 못함 — #{d}"]
        end
        %w(planned_on done_on).each { |f| p[f] = (Date.parse(val.call(f)) rescue p[f]) if cols[f] && val.call(f).present? }
        p.note = val.call('note') if cols['note']
        if p.save
          is_new ? result[:created] += 1 : (result[:updated] += 1 if p.saved_changes.except('updated_at').any?)
        else
          result[:errors] << [start + n + 2, "#{code}: #{p.errors.full_messages.join(', ')}"]
        end
      end
      result
    end

    # ---- 감리 지적사항 (감리 보고서 지적사항 표) — 머리줄 이름으로 칸 찾기, ID 가 같으면 갱신 ----
    AUDIT_FIELDS = {
      'code' => %w(id 번호 지적번호 지적사항id), 'title' => %w(지적사항 제목 지적내용요약 항목), 'content' => %w(내용 상세 지적내용 세부내용),
      'area' => %w(영역 감리영역 분야), 'kind' => %w(구분 유형 조치구분), 'basis' => %w(근거 근거산출물 관련산출물 산출물),
      'plan' => %w(조치계획 개선계획 계획), 'due_on' => %w(기한 조치기한 완료예정일), 'result' => %w(조치결과 결과), 'status' => %w(상태 진행상태)
    }.freeze

    def audits(project, rows, round)
      start = rows.index { |r| r.count { |h| AUDIT_FIELDS.values.flatten.include?(key(h)) } >= 2 }
      return nil unless start
      cols = {}
      rows[start].each_with_index { |h, i| (f = AUDIT_FIELDS.find { |_, n| n.include?(key(h)) }&.first) && cols[f] ||= i }
      return nil unless cols['title'] || cols['content']
      areas = invert('aarea'); kinds = invert('akind'); statuses = invert('astatus')
      result = { created: 0, updated: 0, errors: [] }
      rows[(start + 1)..].to_a.each_with_index do |row, n|
        val = ->(f) { cols[f] ? row[cols[f]].to_s.strip : '' }
        title = val.('title').presence || val.('content').to_s.lines.first.to_s.strip.truncate(200)
        next if title.blank?
        a = val.('code').present? ? PmAudit.where(project_id: project.id).where('UPPER(code) = ?', val.('code').upcase).first : nil
        is_new = a.nil?
        a ||= PmAudit.new(project: project, code: val.('code').presence, pm_audit_round: round, author_id: User.current.id)
        a.title = title.truncate(200)
        a.content = val.('content') if cols['content']
        a.area = areas[key(val.('area'))] || a.area if cols['area']
        a.kind = kinds[key(val.('kind'))] || (val.('kind') =~ /필수|시정/ ? 'correct' : a.kind) if cols['kind']
        a.basis = val.('basis').truncate(200) if cols['basis']
        a.plan = val.('plan') if cols['plan']
        a.result = val.('result') if cols['result']
        a.status = statuses[key(val.('status'))] || a.status if cols['status']
        a.due_on = (Date.parse(val.('due_on')) rescue a.due_on) if cols['due_on'] && val.('due_on').present?
        if a.save
          is_new ? result[:created] += 1 : result[:updated] += 1
        else
          result[:errors] << [start + n + 2, "#{title}: #{a.errors.full_messages.join(', ')}"]
        end
      end
      result
    end

    # ---- 보안 취약점 진단 결과 (도구 결과 엑셀) — 같은 유형·파일·라인은 앞 회차와 이어서 ----
    SEC_FIELDS = {
      'kind' => %w(보안취약점 보안취약점유형 취약점유형 보안약점 보안약점유형 유형 항목 취약점 취약점유형 checker rule 규칙 체커), 'level' => %w(위험도 심각도 등급 severity 중요도 위험),
      'file' => %w(파일 파일경로 경로 file path filepath 소스 소스파일), 'line' => %w(라인 줄 줄번호 line), 'description' => %w(설명 내용 메시지 message 상세)
    }.freeze
    LEVELS = { 'high' => %w(상 높음 high critical major 1 긴급 매우높음), 'low' => %w(하 낮음 low minor info 3 정보) }.freeze

    def sec_level(text)
      t = key(text)
      LEVELS.find { |_, l| l.include?(t) }&.first || 'mid'
    end

    def sec_items(project, scan, rows)
      start = rows.index { |r| r.count { |h| SEC_FIELDS.values.flatten.include?(key(h)) } >= 2 }
      return nil unless start
      cols = {}
      rows[start].each_with_index { |h, i| (f = SEC_FIELDS.find { |_, n| n.include?(key(h)) }&.first) && cols[f] ||= i }
      return nil unless cols['kind']
      progs = PmProgram.where(project_id: project.id).to_a.flat_map { |p| p.paths.map { |x| [x.sub(%r{\A[./\\]+}, '').downcase, p.id] } }
      prev_scan = PmSecScan.where(project_id: project.id).where.not(id: scan.id).sorted.first
      prev = prev_scan ? prev_scan.pm_sec_items.to_a.index_by(&:item_key) : {}
      seen = {}
      result = { created: 0, carried: 0, errors: [] }
      rows[(start + 1)..].to_a.each_with_index do |row, n|
        val = ->(f) { cols[f] ? row[cols[f]].to_s.strip : '' }
        next if val.('kind').blank?
        path = val.('file')
        rel = path.sub(%r{\A[./\\]+}, '').downcase.tr('\\', '/')
        item = scan.pm_sec_items.build(project: project, kind: val.('kind').truncate(150), level: sec_level(val.('level')), file_path: path.truncate(500),
                                       line: val.('line').to_i.positive? ? val.('line').to_i : nil, description: val.('description').presence, status: 'open')
        item.pm_program_id = progs.find { |pa, _| rel.end_with?(pa) || pa.end_with?(rel) }&.last if rel.present?
        key_now = PmSecItem.key_for(item.kind, item.file_path, item.line)
        if (old = prev[key_now]) && old.status == 'except'
          item.status = 'except'; item.reason = old.reason; result[:carried] += 1
        end
        seen[key_now] = true
        if item.save
          result[:created] += 1
        else
          result[:errors] << [start + n + 2, "#{item.kind}: #{item.errors.full_messages.join(', ')}"]
        end
      end
      # 앞 회차: 이번에 없어진 항목은 재진단 통과, 다시 나온 미조치·조치 완료 항목은 재진단 남음
      prev.each_value do |o|
        o.update_columns(recheck: seen[o.item_key] ? (o.status == 'except' ? nil : 'fail') : 'pass')
      end
      result
    end
  end
end
