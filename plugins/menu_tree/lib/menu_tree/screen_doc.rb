# 화면 설계서 (PowerPoint) — 표지 · 개정 이력 · 화면 목록 · 화면마다 1장(캡처 + 화면 정보 + 설명 칸)
# 화면 정보는 메뉴 구조도 · 시스템 권한 · 요구사항(qa_trace) · 프로그램 목록(pm_docs) 에서 자동으로 채움
# 긴 화면(세로로 긴 캡처)은 최대 3장으로 나눠 이어 붙이고, 모바일 캡처가 있으면 모바일 장을 덧붙임
module MenuTree
  module ScreenDoc
    module_function

    INK = '1E2124'
    MUTED = '6D7882'
    NAVY = '052B57'
    HEAD = 'EEF2F7'
    LINE = 'CDD1D5'
    # 화면 장의 자리 (인치)
    IMG = { x: 0.4, y: 1.15, w: 8.55, h: 5.65 }.freeze
    PANEL_X = 9.2
    PANEL_W = 3.73
    MAX_PARTS = 3

    def png_size(data)
      data[16, 8].unpack('NN')
    rescue StandardError
      [nil, nil]
    end

    # 화면 하나의 정보
    def screen_info(project, menu, index, ancestors)
      info = { roles: [], reqs: [], progs: [] }
      if project.module_enabled?(:sys_roles)
        roles = SysRole.where(project_id: project.id).active.sorted.index_by(&:id)
        info[:roles] = MenuRoleAccess.where(menu_item_id: menu.id, sys_role_id: roles.keys).to_a.sort_by { |a| -roles[a.sys_role_id].level }
                                     .map { |a| "#{roles[a.sys_role_id].name}(#{MenuRoleAccess::CODES[a.access]})" }
      end
      if defined?(QaRequirementMenu) && project.module_enabled?(:qa_requirements)
        info[:reqs] = QaRequirement.alive.joins(:qa_requirement_menus).where(qa_requirement_menus: { menu_item_id: [menu.id] + ancestors }).distinct.order(:code).pluck(:code)
      end
      if defined?(PmProgram) && project.module_enabled?(:programs)
        label = defined?(PmKit::Sheet) ? PmKit::Sheet::LABEL['paction'] : {}
        info[:progs] = PmProgram.where(project_id: project.id, menu_item_id: menu.id).order(:code).map do |p|
          acts = p.action_list.map { |a| label[a] || a }.join('·')
          acts.present? ? "#{p.code} #{acts}" : p.code
        end
      end
      info
    end

    def short(list, max)
      list.size > max ? (list.first(max) + ["외 #{list.size - max}"]).join(', ') : list.join(', ')
    end

    def header(s, title, sub, page, total, project)
      s.text(0.4, 0.3, 9.6, 0.62, title, size: 22, bold: true, color: INK, anchor: 'b', inset: 0, name: 'Title')
      s.text(10.0, 0.3, 2.93, 0.62, sub, size: 10, color: MUTED, align: 'r', anchor: 'b', inset: 0)
      s.text(0.4, 7.02, 9, 0.3, "#{project.name} · 화면 설계서", size: 9, color: MUTED, inset: 0)
      s.text(10.93, 7.02, 2, 0.3, "#{page} / #{total}", size: 9, color: MUTED, align: 'r', inset: 0)
    end

    # 그림을 상자 안에 비율 그대로 (가운데) — part: 세로로 나눈 몇 번째 조각
    def place_image(s, data, box, parts: 1, part: 0, alt: '')
      iw, ih = png_size(data)
      return s.text(box[:x], box[:y], box[:w], box[:h], '캡처 이미지를 읽지 못했습니다', size: 12, color: MUTED, align: 'ctr', anchor: 'ctr', line: LINE) unless iw && ih
      seg = (ih.to_f / parts)
      crop_t = seg * part
      crop_b = ih - seg * (part + 1)
      shown_h = seg
      scale = [box[:w] / iw.to_f, box[:h] / shown_h].min
      w = iw * scale
      h = shown_h * scale
      x = box[:x] + (box[:w] - w) / 2
      crop = parts > 1 ? { t: (crop_t / ih * 100_000).round, b: (crop_b / ih * 100_000).round } : nil
      s.image(data, 'png', x, box[:y], w, h, crop: crop, border: LINE, alt: alt)
    end

    # 세로로 긴 캡처를 몇 장으로 나눌지 — 상자 비율로 한 장에 들어가는 높이 기준, 최대 3장
    def parts_for(data, box)
      iw, ih = png_size(data)
      return 1 unless iw && ih
      per = iw * box[:h] / box[:w]
      [[(ih / per).ceil, 1].max, MAX_PARTS].min
    end

    def panel(s, menu, idx, info, cap, y0 = IMG[:y])
      rows = [['화면 ID', menu.screen_id.to_s], ['화면명', menu.name], ['메뉴 경로', menu.path(idx, site: false).truncate(60)],
              ['URL', menu.url.to_s.truncate(70)], ['화면 유형', MenuTree::Sheet::TYPE_LABELS[menu.screen_type].to_s],
              ['메뉴 노출', menu.in_menu? ? 'Y' : 'N (화면만)'], ['접근 권한', short(info[:roles], 4)], ['요구사항', short(info[:reqs], 6)],
              ['프로그램', short(info[:progs], 4)], ['캡처 일시', cap ? cap.captured_at.in_time_zone(User.current.time_zone || Time.zone).strftime('%Y-%m-%d %H:%M') : '캡처 없음']]
      s.table(PANEL_X, y0, [1.0, PANEL_W - 1.0], rows.map { |k, v| [{ text: k, bold: true, fill: HEAD, color: NAVY }, v.presence || '-'] }, row_h: 0.33, size: 9)
      top = y0 + 0.33 * rows.size + 0.25
      s.text(PANEL_X, top, PANEL_W, 0.3, '화면 설명', size: 10, bold: true, color: NAVY, inset: 0)
      s.rect(PANEL_X, top + 0.32, PANEL_W, [IMG[:y] + IMG[:h] - top - 0.32, 0.6].max, line: LINE, name: '화면 설명 칸')
    end

    # captures: { [menu_id, kind] => MenuCapture } 최신 정상 캡처
    def build(project, site: nil, author: User.current)
      ordered = MenuItem.ordered(project, site: site&.id)
      idx = MenuItem.where(project_id: project.id).index_by(&:id)
      screens = MenuItem.screens(ordered)
      caps = MenuCapture.ok.where(menu_item_id: screens.map(&:id)).order(captured_at: :desc).to_a.group_by { |c| [c.menu_item_id, c.kind] }.transform_values(&:first)
      data = ->(c) { c && c.path && File.file?(c.path) ? File.binread(c.path) : nil }
      today = User.current.today
      # 장 수를 먼저 셈 (쪽 번호)
      plan = screens.map do |m|
        pc = data.(caps[[m.id, 'pc']])
        mob = data.(caps[[m.id, 'mobile']])
        { menu: m, pc: pc, mob: mob, parts: pc ? parts_for(pc, IMG) : 1 }
      end
      list_pages = [(screens.size / 15.0).ceil, 1].max
      total = 2 + list_pages + plan.sum { |p| p[:parts] + (p[:mob] ? 1 : 0) }
      first_page = {}
      page = 2 + list_pages
      plan.each { |p| first_page[p[:menu].id] = page + 1; page += p[:parts] + (p[:mob] ? 1 : 0) }

      deck = KrdsUi::Pptx.new(title: "#{project.name} 화면 설계서", author: author.to_s)
      site_names = site ? [site.name] : MenuSite.where(project_id: project.id).sorted.pluck(:name)
      latest = caps.values.map(&:captured_at).max

      # 1. 표지 — 왼쪽 글, 오른쪽 대표 화면 4개
      s = deck.slide
      s.text(0.8, 1.9, 6.3, 0.9, '화면 설계서', size: 40, bold: true, color: NAVY, inset: 0, name: 'Title')
      s.text(0.8, 2.9, 6.3, 0.6, project.name, size: 20, bold: true, color: INK, inset: 0)
      meta = [['사이트', site_names.join(', ').presence || project.name], ['화면 수', "#{screens.size}개 (캡처 #{plan.count { |p| p[:pc] }}개)"],
              ['작성일', today.strftime('%Y-%m-%d')], ['버전', 'v1.0'], ['캡처 기준', latest ? latest.in_time_zone(User.current.time_zone || Time.zone).strftime('%Y-%m-%d %H:%M') : '-']]
      s.table(0.8, 3.9, [1.3, 4.6], meta.map { |k, v| [{ text: k, bold: true, fill: HEAD, color: NAVY }, v] }, row_h: 0.38, size: 12)
      s.text(0.8, 6.5, 6.3, 0.4, 'PMS 메뉴 구조도 · 운영 화면 캡처로 자동 생성', size: 10, color: MUTED, inset: 0)
      thumbs = plan.select { |p| p[:pc] }.first(4)
      thumbs.each_with_index do |p, i|
        box = { x: 7.55 + (i % 2) * 2.75, y: 1.6 + (i / 2) * 2.25, w: 2.55, h: 2.0 }
        place_image(s, p[:pc], box, parts: parts_for(p[:pc], box), alt: p[:menu].name)
      end

      # 2. 개정 이력
      s = deck.slide
      header(s, '개정 이력', '', 2, total, project)
      rows = [[{ text: '버전', bold: true, fill: HEAD, color: NAVY, align: 'ctr' }, { text: '일자', bold: true, fill: HEAD, color: NAVY, align: 'ctr' },
               { text: '변경 내용', bold: true, fill: HEAD, color: NAVY, align: 'ctr' }, { text: '작성자', bold: true, fill: HEAD, color: NAVY, align: 'ctr' }],
              [{ text: 'v1.0', align: 'ctr' }, { text: today.strftime('%Y-%m-%d'), align: 'ctr' }, '최초 작성 (운영 화면 캡처 기준)', { text: author.to_s, align: 'ctr' }]] +
             Array.new(8) { ['', '', '', ''] }
      s.table(0.4, 1.15, [1.4, 2.0, 7.13, 2.0], rows, row_h: 0.42, size: 12)

      # 3. 화면 목록 (15줄씩)
      head = %w(번호 화면\ ID 화면명 메뉴\ 경로 화면\ 유형 쪽).map { |t| { text: t, bold: true, fill: HEAD, color: NAVY, align: 'ctr' } }
      head.insert(1, { text: '사이트', bold: true, fill: HEAD, color: NAVY, align: 'ctr' }) if site_names.size > 1
      screens.each_slice(15).with_index.to_a.then { |sl| sl.empty? ? [[[], 0]] : sl }.each do |chunk, n|
        s = deck.slide
        header(s, "화면 목록#{" (#{n + 1}/#{list_pages})" if list_pages > 1}", '', 3 + n, total, project)
        body = chunk.each_with_index.map do |m, i|
          row = [{ text: (n * 15 + i + 1).to_s, align: 'ctr' }, m.screen_id.to_s, m.name.truncate(30), m.path(idx, site: false).truncate(50),
                 { text: MenuTree::Sheet::TYPE_LABELS[m.screen_type].to_s, align: 'ctr' }, { text: first_page[m.id].to_s, align: 'ctr' }]
          row.insert(1, { text: m.menu_site&.name.to_s, align: 'ctr' }) if site_names.size > 1
          row
        end
        widths = site_names.size > 1 ? [0.6, 1.4, 1.6, 2.5, 4.53, 1.2, 0.7] : [0.7, 1.7, 2.7, 5.33, 1.4, 0.7]
        s.table(0.4, 1.15, widths, [head] + body, row_h: 0.36, size: 10)
        s.text(0.4, 1.15, 12.53, 0.5, '화면이 없습니다 — 메뉴 구조도에 화면(화면 유형·화면 ID)을 넣어 주세요', size: 12, color: MUTED, inset: 0) if chunk.empty?
      end

      # 4. 화면마다
      plan.each do |p|
        m = p[:menu]
        anc = []
        x = m
        while x.parent_id && (pa = idx[x.parent_id])
          anc << pa.id
          x = pa
        end
        info = screen_info(project, m, idx, anc)
        cap = caps[[m.id, 'pc']]
        sub = [m.site_label, m.path(idx, site: false)].compact.join(' · ').truncate(45)
        pg = first_page[m.id]
        p[:parts].times do |part|
          s = deck.slide
          cont = p[:parts] > 1 ? " (#{part + 1}/#{p[:parts]})" : ''
          header(s, "#{[m.screen_id, m.name].compact.join('  ')}#{cont}", sub, pg + part, total, project)
          if p[:pc]
            place_image(s, p[:pc], IMG, parts: p[:parts], part: part, alt: m.name)
          else
            s.text(IMG[:x], IMG[:y], IMG[:w], IMG[:h], m.url.present? ? '캡처 없음 — 화면 캡처를 실행하세요' : 'URL 없음 — 메뉴 구조도에 URL 을 넣으면 캡처할 수 있습니다',
                   size: 14, color: MUTED, align: 'ctr', anchor: 'ctr', line: LINE)
          end
          if part.zero?
            panel(s, m, idx, info, cap)
          else
            s.text(PANEL_X, IMG[:y], PANEL_W, 0.6, "앞 장(#{pg}쪽)에 이어지는 화면입니다.", size: 11, color: MUTED, inset: 0)
          end
        end
        next unless p[:mob]
        s = deck.slide
        header(s, "#{[m.screen_id, m.name].compact.join('  ')} (모바일)", sub, pg + p[:parts], total, project)
        box_w = 2.6
        mparts = [parts_for(p[:mob], { w: box_w, h: IMG[:h] }), 3].min
        mparts.times do |k|
          place_image(s, p[:mob], { x: IMG[:x] + k * (box_w + 0.3), y: IMG[:y], w: box_w, h: IMG[:h] }, parts: mparts, part: k, alt: "#{m.name} 모바일")
        end
        panel(s, m, idx, info, caps[[m.id, 'mobile']])
      end
      deck.to_s
    end
  end
end
