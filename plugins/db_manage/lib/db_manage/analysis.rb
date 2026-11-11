# 스키마 비교(개발 ↔ 운영)와 용어사전 점검 (컬럼명 ↔ 용어사전 약어)
module DbManage
  module Analysis
    module_function

    COMPARE_FIELDS = %i(type nullable default comment keys).freeze
    TYPE_ALIASES = {
      'character varying' => 'varchar', 'varchar2' => 'varchar', 'nvarchar' => 'varchar', 'character' => 'char',
      'integer' => 'int', 'int4' => 'int', 'int8' => 'bigint', 'int2' => 'smallint', 'numeric' => 'decimal', 'number' => 'decimal',
      'timestamp without time zone' => 'timestamp', 'timestamp with time zone' => 'timestamptz', 'double precision' => 'double',
      'bool' => 'boolean', 'clob' => 'text', 'longtext' => 'text', 'mediumtext' => 'text'
    }.freeze

    # a, b: Connector#snapshot 결과
    def compare(a, b)
      ta = a[:tables].index_by { |t| t[:name] }
      tb = b[:tables].index_by { |t| t[:name] }
      result = { only_a: (ta.keys - tb.keys).sort.map { |n| ta[n] }, only_b: (tb.keys - ta.keys).sort.map { |n| tb[n] }, changed: [], same: 0 }
      (ta.keys & tb.keys).sort.each do |name|
        ca = (a[:columns][name] || []).index_by { |c| c[:name] }
        cb = (b[:columns][name] || []).index_by { |c| c[:name] }
        diffs = []
        (ca.keys | cb.keys).each do |col|
          x = ca[col]; y = cb[col]
          if x.nil? then diffs << { column: col, kind: :only_b, b: y }
          elsif y.nil? then diffs << { column: col, kind: :only_a, a: x }
          else
            fields = COMPARE_FIELDS.reject { |f| x[f] == y[f] }
            diffs << { column: col, kind: :changed, a: x, b: y, fields: fields } if fields.any?
          end
        end
        if diffs.any? || ta[name][:comment] != tb[name][:comment]
          result[:changed] << { table: name, comment_a: ta[name][:comment], comment_b: tb[name][:comment], diffs: diffs }
        else
          result[:same] += 1
        end
      end
      result
    end

    # 테이블 외 객체(뷰·함수·프로시저·트리거·DB 잡·시퀀스) 비교: 한쪽에만 있음 / 정의 다름
    # MariaDB 뷰 정의에는 스키마 이름이 들어가므로(`sample_dev`.`TB`) 지우고, 공백은 하나로 맞춰 비교
    def compare_objects(a, b, schema_a, schema_b)
      kinds = ((a[:kinds] || []) | (b[:kinds] || [])) - ['table']
      kinds.filter_map do |kind|
        la = a.dig(:objects, kind); lb = b.dig(:objects, kind)
        next if la.nil? && lb.nil?
        ia = (la || []).index_by { |o| o[:key] }; ib = (lb || []).index_by { |o| o[:key] }
        rows = []
        (ia.keys - ib.keys).sort.each { |k| rows << { kind: kind, key: k, name: ia[k][:name], state: :only_a } }
        (ib.keys - ia.keys).sort.each { |k| rows << { kind: kind, key: k, name: ib[k][:name], state: :only_b } }
        (ia.keys & ib.keys).sort.each do |k|
          da = norm_def(ia[k][:definition], schema_a); db = norm_def(ib[k][:definition], schema_b)
          state = if da.nil? || db.nil? then (da == db ? nil : :unknown)
                  elsif da != db then :changed
                  end
          rows << { kind: kind, key: k, name: ia[k][:name], state: state } if state
        end
        same = (ia.keys & ib.keys).size - rows.count { |r| %i(changed unknown).include?(r[:state]) }
        { kind: kind, rows: rows, same: same }
      end
    end

    def norm_def(text, schema)
      return nil if text.blank?
      t = text.to_s.gsub(/`#{Regexp.escape(schema.to_s)}`\./, '').gsub(/"?#{Regexp.escape(schema.to_s)}"?\./, '')
      t.gsub(/\s+/, ' ').strip
    end

    # 약어(대문자) → 용어. 같은 약어가 있으면 프로젝트 용어 우선. 용어사전 플러그인이 없으면 nil
    def term_map(project)
      return nil unless defined?(GlossaryTerm)
      GlossaryTerm.for_project(project).where.not(abbr: [nil, '']).order(Arel.sql('project_id IS NULL'), :name)
                  .each_with_object({}) { |t, map| map[t.abbr.upcase] ||= t }
    end

    # [:ok | :type | :missing, 용어]
    def term_status(column, map)
      term = map[column[:name].to_s.upcase]
      return [:missing, nil] unless term
      return [:ok, term] if term.data_type.blank?
      base, len = split_type(column[:type])
      tbase = normalize(term.data_type)
      tlen = term.data_length.to_s.delete(' ')
      ok = base == tbase && (tlen.empty? || tlen == len.to_s)
      [ok ? :ok : :type, term]
    end

    def split_type(type)
      t = type.to_s.downcase.sub(/\s+unsigned\b.*/, '').strip
      len = t[/\(([^)]*)\)/, 1].to_s.delete(' ')
      base = normalize(t.sub(/\([^)]*\)/, ''))
      len = '' if %w(int bigint smallint tinyint mediumint).include?(base)
      [base, len]
    end

    def normalize(type)
      t = type.to_s.downcase.squeeze(' ').strip
      TYPE_ALIASES.fetch(t, t)
    end
  end
end
