# 메뉴 구조도 ↔ 엑셀 표 (가져오기·내보내기 같은 양식)
# 머리줄: 1뎁스 2뎁스 … | 화면 ID | URL | 화면 유형 | 채널 | 사용 | (추가 칼럼…) | 비고  (+ 내보내기 전용: 대상 권한·일감 수·완료·진행률)
# 가져오기: 위 칸이 비어 있으면 바로 윗줄 값을 이어받음(엑셀 셀 병합·생략 모두 가능), 같은 경로의 메뉴는 합침
module MenuTree
  module Sheet
    module_function

    DEPTH = [/\A(\d+)\s*(뎁스|depth|단계|레벨|level|차|dep)\z/i, /\A(depth|level|레벨|뎁스|lv)\s*\.?\s*(\d+)\z/i].freeze
    NAMED = { '대메뉴' => 1, '중메뉴' => 2, '소메뉴' => 3, '세메뉴' => 4, '세부메뉴' => 4 }.freeze
    FIELDS = {
      'screen_id' => %w(화면id 화면아이디 프로그램id 프로그램아이디 screenid 화면번호 메뉴id),
      'url' => %w(url 경로 주소 링크 uri),
      'screen_type' => %w(화면유형 유형 화면구분 type),
      'channel' => %w(채널 기기 pc/모바일 대상기기 channel),
      'active' => %w(사용 사용여부 사용유무 active),
      'note' => %w(비고 설명 메모 note 참고)
    }.freeze
    EXPORT_ONLY = %w(대상권한 대상 일감수 일감 완료 진행률).freeze
    TYPE_LABELS = { 'list' => '목록', 'detail' => '상세', 'form' => '등록·수정', 'popup' => '팝업', 'tab' => '탭', 'link' => '링크' }.freeze
    CHANNEL_LABELS = { 'both' => '공통', 'pc' => 'PC', 'mobile' => '모바일' }.freeze

    def key(h)
      h.to_s.downcase.gsub(/[\s_·\-()]/, '')
    end

    def depth_of(header)
      h = header.to_s.strip
      return NAMED[h.delete(' ')] if NAMED[h.delete(' ')]
      DEPTH.each { |re| (m = h.match(re)) && (return (m[1] =~ /\d/ ? m[1] : m[2]).to_i) }
      nil
    end

    def type_code(v)
      s = v.to_s.strip
      return nil if s.empty?
      return s.downcase if TYPE_LABELS.key?(s.downcase)
      { '목록' => 'list', '리스트' => 'list', '조회' => 'list', '상세' => 'detail', '등록·수정' => 'form', '등록' => 'form', '수정' => 'form',
        '등록/수정' => 'form', '입력' => 'form', '팝업' => 'popup', '탭' => 'tab', '링크' => 'link' }[s.delete(' ')]
    end

    def channel_code(v)
      s = v.to_s.strip.downcase
      return nil if s.empty?
      return s if CHANNEL_LABELS.key?(s)
      { '공통' => 'both', 'pc/모바일' => 'both', 'pc,모바일' => 'both', '모두' => 'both', 'pc' => 'pc', '웹' => 'pc', '모바일' => 'mobile', 'mo' => 'mobile', 'app' => 'mobile', '앱' => 'mobile' }[s.delete(' ')]
    end

    def active_value(v)
      s = v.to_s.strip.downcase
      return true if s.empty?
      !%w(n no 미사용 x false 0 폐기 사용안함).include?(s)
    end

    # rows: 2차원 배열. 반환: { created:, updated:, columns: [새 칼럼 이름], errors: [[줄, 메시지]] }
    def import(project, rows, replace: false, author: nil, new_columns: true)
      header_idx = rows.index { |r| r.any? { |c| depth_of(c) } }
      return nil unless header_idx
      header = rows[header_idx]
      depth_cols = {}
      field_cols = {}
      extra_cols = {}
      result = { created: 0, updated: 0, columns: [], errors: [] }
      columns = project_columns(project)
      header.each_with_index do |h, i|
        next if h.blank?
        if (d = depth_of(h))
          depth_cols[d] = i
        elsif (f = FIELDS.find { |_, names| names.include?(key(h)) }&.first)
          field_cols[f] ||= i
        elsif EXPORT_ONLY.include?(key(h))
          next
        else
          col = columns.find { |c| c.name.casecmp?(h.strip) }
          if col.nil? && new_columns
            col = MenuColumn.create!(project: project, name: h.strip.truncate(60), kind: 'text', position: (MenuColumn.where(project_id: project.id).maximum(:position) || 0) + 1)
            columns << col
            result[:columns] << col.name
          end
          extra_cols[col.id.to_s] = [i, col] if col
        end
      end
      levels = depth_cols.keys.sort
      MenuItem.transaction do
        MenuItem.where(project_id: project.id, parent_id: nil).destroy_all if replace
        existing = MenuItem.where(project_id: project.id).to_a
        children = existing.group_by(&:parent_id)
        stack = []
        rows[(header_idx + 1)..].to_a.each_with_index do |row, n|
          line = header_idx + n + 2
          names = levels.map { |d| row[depth_cols[d]].to_s.strip.presence }
          last = names.rindex { |v| v }
          next unless last
          path = (0..last).map { |k| names[k] || stack[k] }
          if path.any?(&:nil?)
            result[:errors] << [line, '윗 뎁스 메뉴 이름이 없습니다']
            next
          end
          stack = path.dup
          parent = nil
          path.each_with_index do |name, k|
            siblings = children[parent&.id] ||= []
            node = siblings.find { |m| m.name.casecmp?(name) }
            unless node
              node = MenuItem.new(project: project, parent: parent, name: name.truncate(150), author_id: author&.id,
                                  position: (siblings.map(&:position).max || 0) + 1)
              node.save!
              siblings << node
              result[:created] += 1
              created_now = true
            end
            if k == last
              attrs = {}
              attrs[:screen_id] = row[field_cols['screen_id']] if field_cols['screen_id']
              attrs[:url] = row[field_cols['url']] if field_cols['url']
              attrs[:screen_type] = type_code(row[field_cols['screen_type']]) if field_cols['screen_type']
              attrs[:channel] = channel_code(row[field_cols['channel']]) if field_cols['channel']
              attrs[:active] = active_value(row[field_cols['active']]) if field_cols['active']
              attrs[:note] = row[field_cols['note']] if field_cols['note']
              extra = node.extra.dup
              extra_cols.each { |cid, (i, col)| v = col.cast(row[i]); v ? extra[cid] = v : extra.delete(cid) }
              node.assign_attributes(attrs.merge(extra: extra))
              if node.changed?
                if node.save
                  result[:updated] += 1 unless created_now
                else
                  result[:errors] << [line, "#{name}: #{node.errors.full_messages.join(', ')}"]
                end
              end
            end
            parent = node
          end
        end
      end
      result
    end

    def project_columns(project)
      MenuColumn.where(project_id: project.id).sorted.to_a
    end

    # 내보내기 표: [머리줄, 행들]
    def export(project, ordered, columns, stats, roles)
      max = (ordered.map(&:last).max || 0) + 1
      header = (1..max).map { |d| "#{d}뎁스" } + %w(화면\ ID URL 화면\ 유형 채널 사용) + columns.map(&:name) +
               (roles ? ['대상 권한'] : []) + %w(일감\ 수 완료 진행률 비고)
      rows = ordered.map do |m, depth|
        s = stats[m.id] || {}
        Array.new(depth) + [m.name] + Array.new(max - depth - 1) +
          [m.screen_id, m.url, TYPE_LABELS[m.screen_type], CHANNEL_LABELS[m.channel], m.active? ? 'Y' : 'N'] +
          columns.map { |c| v = m.extra[c.id.to_s]; c.kind == 'bool' ? (v ? 'Y' : nil) : v } +
          (roles ? [(roles[m.id] || []).map { |n, code| "#{n}(#{code})" }.join(', ')] : []) +
          [s[:total].to_i.positive? ? s[:total] : nil, s[:total].to_i.positive? ? s[:closed] : nil, s[:total].to_i.positive? ? "#{s[:ratio]}%" : nil, m.note]
      end
      [header, rows, max]
    end
  end
end
