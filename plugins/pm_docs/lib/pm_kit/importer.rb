# 프로그램 목록 엑셀 가져오기 — 머리줄 이름으로 칸 찾기, 프로그램 ID 가 같으면 갱신
module PmKit
  module Importer
    module_function

    FIELDS = {
      'code' => %w(프로그램id 프로그램아이디 프로그램번호 id), 'name' => %w(프로그램명 이름 프로그램이름), 'kind' => %w(유형 구분 종류),
      'menu' => %w(화면id 메뉴 화면 메뉴경로), 'paths' => %w(소스경로 소스 경로 파일), 'developer' => %w(개발자 담당 담당자),
      'status' => %w(상태 진척), 'planned_on' => %w(계획일 완료예정일), 'done_on' => %w(완료일), 'note' => %w(비고)
    }.freeze

    def key(h)
      h.to_s.downcase.gsub(/[\s_·\-().\/]/, '')
    end

    def invert(group)
      PmKit::Sheet::LABEL[group].to_h { |k, v| [key(v), k] }
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
      by_path = menus.index_by { |m| key(m.path(index)) }
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
  end
end
