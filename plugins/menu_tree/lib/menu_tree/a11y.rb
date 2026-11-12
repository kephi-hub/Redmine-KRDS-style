# 웹 접근성 자동 점검 — 화면을 캡처할 때 axe-core(vendor/, 4.10.3, MPL-2.0, 한국어 메시지)로 검사해
# 위반을 한국형 웹 콘텐츠 접근성 지침(KWCAG 2.2) 항목으로 묶어 MenuCapture#a11y 에 저장
# 자동 점검은 KWCAG 일부(대체 텍스트·명도 대비·레이블·제목·언어·마크업 등)만 확인한다 —
# 키보드 사용·초점·자막·깜빡임·오류 정정 등은 사람이 직접 확인해야 함 (화면·엑셀에 안내)
module MenuTree
  module A11y
    module_function

    VENDOR = File.expand_path('../../vendor', __dir__)
    TAGS = %w(wcag2a wcag2aa wcag21a wcag21aa wcag22aa).freeze

    # KWCAG 2.2 — 4원칙 · 14지침 · 33검사항목
    ITEMS = {
      '5.1.1' => '적절한 대체 텍스트 제공', '5.2.1' => '자막 제공', '5.3.1' => '표의 구성', '5.3.2' => '콘텐츠의 선형구조',
      '5.3.3' => '명확한 지시사항 제공', '5.4.1' => '색에 무관한 콘텐츠 인식', '5.4.2' => '자동 재생 금지', '5.4.3' => '텍스트 콘텐츠의 명도 대비',
      '5.4.4' => '콘텐츠 간의 구분', '6.1.1' => '키보드 사용 보장', '6.1.2' => '초점 이동과 표시', '6.1.3' => '조작 가능', '6.1.4' => '문자 단축키',
      '6.2.1' => '응답시간 조절', '6.2.2' => '정지 기능 제공', '6.3.1' => '깜빡임과 번쩍임 사용 제한', '6.4.1' => '반복 영역 건너뛰기',
      '6.4.2' => '제목 제공', '6.4.3' => '적절한 링크 텍스트', '6.4.4' => '고정된 참조 위치 정보', '6.5.1' => '단일 포인터 입력 지원',
      '6.5.2' => '포인터 입력 취소', '6.5.3' => '레이블과 네임', '6.5.4' => '동작기반 작동', '7.1.1' => '기본 언어 표시',
      '7.2.1' => '사용자 요구에 따른 실행', '7.2.2' => '찾기 쉬운 도움 정보', '7.3.1' => '오류 정정', '7.3.2' => '레이블 제공',
      '7.3.3' => '접근 가능한 인증', '7.3.4' => '반복 입력 정보', '8.1.1' => '마크업 오류 방지', '8.2.1' => '웹 애플리케이션 접근성 준수'
    }.freeze

    # 자동 점검으로 확인할 수 있는 항목 (나머지는 사람이 확인)
    AUTO_ITEMS = %w(5.1.1 5.2.1 5.3.1 5.3.2 5.4.1 5.4.2 5.4.3 6.1.1 6.1.2 6.1.4 6.2.1 6.2.2 6.4.1 6.4.2 6.4.3 6.5.3 7.1.1 7.3.2 8.1.1 8.2.1).freeze

    # axe 규칙 → KWCAG 항목 (없는 규칙은 aria-* 면 8.2.1, 아니면 '기타')
    RULES = {
      %w(image-alt input-image-alt area-alt role-img-alt svg-img-alt object-alt image-redundant-alt server-side-image-map) => '5.1.1',
      %w(video-caption audio-caption) => '5.2.1',
      %w(td-headers-attr th-has-data-cells td-has-header scope-attr-valid table-duplicate-name table-fake-caption) => '5.3.1',
      %w(list listitem definition-list dlitem) => '5.3.2',
      %w(link-in-text-block) => '5.4.1',
      %w(no-autoplay-audio) => '5.4.2',
      %w(color-contrast color-contrast-enhanced) => '5.4.3',
      %w(scrollable-region-focusable frame-focusable-content nested-interactive) => '6.1.1',
      %w(tabindex focus-order-semantics) => '6.1.2',
      %w(accesskeys) => '6.1.4',
      %w(meta-refresh meta-refresh-no-exceptions) => '6.2.1',
      %w(blink marquee) => '6.2.2',
      %w(bypass skip-link) => '6.4.1',
      %w(document-title frame-title frame-title-unique page-has-heading-one empty-heading heading-order empty-table-header) => '6.4.2',
      %w(link-name) => '6.4.3',
      %w(label-content-name-mismatch) => '6.5.3',
      %w(html-has-lang html-lang-valid html-xml-lang-mismatch valid-lang) => '7.1.1',
      %w(label select-name input-button-name form-field-multiple-labels autocomplete-valid label-title-only) => '7.3.2',
      %w(duplicate-id duplicate-id-aria duplicate-id-active) => '8.1.1',
      %w(button-name frame-tested meta-viewport meta-viewport-large target-size) => '8.2.1'
    }.flat_map { |rules, item| rules.map { |r| [r, item] } }.to_h.freeze

    IMPACTS = %w(critical serious moderate minor).freeze
    IMPACT_NAMES = { 'critical' => '치명', 'serious' => '심각', 'moderate' => '보통', 'minor' => '경미' }.freeze

    def kwcag(rule)
      RULES[rule] || (rule.to_s.start_with?('aria-') ? '8.2.1' : nil)
    end

    def item_name(code)
      code ? "#{code} #{ITEMS[code]}" : '기타'
    end

    def script
      @script ||= File.read(File.join(VENDOR, 'axe.min.js'))
    end

    def locale
      @locale ||= File.read(File.join(VENDOR, 'axe-ko.json'))
    end

    def available?
      File.file?(File.join(VENDOR, 'axe.min.js'))
    end

    # 화면마다 최근 점검 결과 [[메뉴, 캡처 or nil]]
    def latest(project, site: nil)
      ordered = MenuItem.ordered(project, site: site&.id)
      screens = MenuItem.screens(ordered)
      caps = MenuCapture.where(menu_item_id: screens.map(&:id), kind: 'pc').where.not(a11y_count: nil).order(:captured_at).to_a.index_by(&:menu_item_id)
      [ordered.to_h { |m, _| [m.id, m] }, screens.map { |m| [m, caps[m.id]] }]
    end

    # 점검표 엑셀 — 요약(KWCAG 항목별) · 화면별 위반 · 화면별 건수
    def sheet(project, site: nil)
      index, list = latest(project, site: site)
      checked = list.select { |_, c| c }
      rows = []
      by_item = Hash.new { |h, k| h[k] = { screens: Set.new, nodes: 0 } }
      checked.each do |m, c|
        c.a11y_list.each do |v|
          by_item[v['kwcag']][:screens] << m.id
          by_item[v['kwcag']][:nodes] += v['n'].to_i
          rows << [m.screen_id, m.name, m.path(index, site: false), c.captured_at.localtime.strftime('%Y-%m-%d %H:%M'), item_name(v['kwcag']), v['id'],
                   IMPACT_NAMES[v['impact']] || v['impact'], v['help'], v['n'], Array(v['targets']).join("\n"), v['url']]
        end
      end
      summary = ITEMS.map do |code, name|
        auto = AUTO_ITEMS.include?(code)
        hit = by_item[code] if by_item.key?(code)
        [code, name, auto ? '자동 + 수동' : '수동 확인', hit ? '위반' : (auto ? '자동 점검 위반 없음' : '-'), hit ? hit[:screens].size : nil, hit ? hit[:nodes] : nil]
      end
      if by_item.key?(nil)
        summary << ['기타', 'KWCAG 항목에 없는 WCAG 규칙', '자동', '위반', by_item[nil][:screens].size, by_item[nil][:nodes]]
      end
      per = list.map do |m, c|
        [m.screen_id, m.name, m.path(index, site: false), c ? c.captured_at.localtime.strftime('%Y-%m-%d %H:%M') : '점검 안 함', c&.a11y_count, c&.a11y_nodes,
         c ? IMPACTS.map { |i| c.a11y_list.count { |v| v['impact'] == i } }.join(' / ') : nil]
      end
      note = [['자동 점검 도구', "axe-core #{script[/axe v([\d.]+)/, 1]} (WCAG 2.2 A·AA 규칙) → KWCAG 2.2 항목으로 묶음"],
              ['점검 화면', "#{checked.size} / #{list.size}"],
              ['주의', '자동 점검은 KWCAG 33개 항목 중 일부만 확인합니다. 키보드 사용·초점·자막·깜빡임·오류 정정·인증 등은 사람이 직접 확인해야 합니다.']]
      KrdsUi::Xlsx.build([
        { name: 'KWCAG 항목별 요약', header: %w(항목 이름 점검\ 방법 결과 위반\ 화면 위반\ 요소), rows: summary, widths: [8, 28, 12, 20, 10, 10] },
        { name: '화면별 위반', header: %w(화면\ ID 화면 메뉴\ 경로 점검\ 시각 KWCAG 규칙 심각도 설명 요소\ 수 예시\ 위치 참고), rows: rows,
          widths: [12, 20, 36, 16, 28, 22, 8, 50, 8, 50, 40] },
        { name: '화면별 건수', header: %w(화면\ ID 화면 메뉴\ 경로 점검\ 시각 위반\ 규칙 위반\ 요소 치명/심각/보통/경미), rows: per, widths: [12, 20, 36, 16, 10, 10, 18] },
        { name: '안내', header: %w(구분 내용), rows: note, widths: [16, 100] }
      ])
    end

    # 화면 하나의 위반을 결함 일감으로 (결함 유형이 없으면 첫 유형) — 메뉴와 연결
    def make_issue(project, menu, cap, user)
      index = MenuItem.where(project_id: project.id).index_by(&:id)
      tracker = project.trackers.find_by(name: '결함') || project.trackers.first
      issue = Issue.new(project: project, tracker: tracker, author: user)
      issue.subject = "[웹 접근성] #{menu.name}#{" (#{menu.screen_id})" if menu.screen_id} 위반 #{cap.a11y_count}건".truncate(255)
      lines = ["- 메뉴: #{menu.path(index)}", ("- URL: #{cap.url}" if cap.url), "- 점검: #{cap.captured_at.localtime.strftime('%Y-%m-%d %H:%M')} (axe-core 자동 점검)", '']
      cap.a11y_list.each do |v|
        lines << "- [#{IMPACT_NAMES[v['impact']] || v['impact']}] #{item_name(v['kwcag'])} — #{v['help']} (#{v['id']}, #{v['n']}곳)"
        Array(v['targets']).each { |t| lines << "    - `#{t.delete('`')}`" }
      end
      issue.description = lines.compact.join("\n")
      if issue.save && defined?(MenuItemIssue)
        MenuItemIssue.create!(menu_item_id: menu.id, issue_id: issue.id)
      end
      issue
    end

    # 지금 화면을 검사 → [{ 'id', 'kwcag', 'impact', 'help', 'url', 'n', 'targets' }] (위반 없으면 [])
    # 페이지의 AMD(define)·CommonJS 와 엉키지 않게 함수 안에서 불러 window.axe 로만 씀
    def check(b)
      b.execute("(function(){var define, module, exports; #{script}\n}).call(window); window.axe.configure({ locale: #{locale} });")
      # Ferrum evaluate_async: 맨 바깥의 arguments[0] 이 결과를 돌려주는 콜백
      res = b.evaluate_async(<<~JS, 60)
        var done = arguments[0];
        window.axe.run(document, { runOnly: { type: 'tag', values: #{TAGS.to_json} }, resultTypes: ['violations'] })
          .then(function (r) {
            done(r.violations.map(function (v) {
              return { id: v.id, impact: v.impact, help: v.help, url: v.helpUrl, n: v.nodes.length,
                       targets: v.nodes.slice(0, 3).map(function (x) { return [].concat(x.target).join(' ').slice(0, 200); }) };
            }));
          })
          .catch(function (e) { done({ error: String(e) }); });
      JS
      raise(res['error'].to_s) if res.is_a?(Hash)
      Array(res).map { |v| v.merge('kwcag' => kwcag(v['id'])) }
               .sort_by { |v| [IMPACTS.index(v['impact']) || 9, v['kwcag'] || '9', v['id']] }
    end
  end
end
