# 이관 엔진 — PostgreSQL
# - 구조: pg_catalog 에서 칼럼(format_type·기본값·IDENTITY·생성 칼럼·설명)·제약(pg_get_constraintdef)·인덱스(pg_get_indexdef) → CREATE / ALTER
#   두 세션 search_path 를 각 스키마로 두어 정의가 스키마 없이 나오게 함. nextval 기본값의 시퀀스는 없으면 만들고 데이터 뒤 값 맞춤
# - 데이터: 원본 COPY TO STDOUT → 대상 임시 테이블 COPY FROM STDIN (텍스트 형식 그대로) → 한 트랜잭션에서 반영
#   replace: 기본키가 있으면 원본에 없는 행 삭제 + INSERT … ON CONFLICT DO UPDATE (지우지 않는 행은 외래키에 걸리지 않음), 없으면 DELETE 후 INSERT
#   쓰기 계정이 슈퍼유저면 session_replication_role = replica 로 외래키·트리거 검사를 끔 (아니면 참조되는 테이블 순서대로)
# - 백업: DROP + CREATE + COPY … FROM stdin (psql 로 실행하면 복원)
module DbManage
  class MigratePostgresql < MigrateBase
    def q(name)
      %("#{name.to_s.gsub('"', '""')}")
    end

    def prepare
      c.exec("SET search_path TO #{q(schema)}")
      c.exec("SET TIME ZONE 'UTC'")
      c.exec("SET DateStyle = 'ISO, YMD'")
      c.exec("SET IntervalStyle = 'postgres'")
      c.exec('SET extra_float_digits = 3')
      c.exec("SET bytea_output = 'hex'")
      c.exec("SET client_encoding = 'UTF8'")
      return unless @write
      @replica = begin
        c.exec('SET session_replication_role = replica')
        true
      rescue PG::Error
        false
      end
    end

    # 미리보기 알림 — 쓰기 계정이 슈퍼유저가 아니면 외래키 검사를 끌 수 없음
    def notes
      [t(:text_db_mig_pg_fk)]
    end

    def exec(sql)
      c.exec(sql)
    end

    def count(name)
      c.exec("SELECT COUNT(*) FROM #{q(name)}").getvalue(0, 0).to_i
    end

    def row_estimates
      c.exec_params("SELECT c.relname, GREATEST(c.reltuples, 0)::bigint FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace " \
                    "WHERE n.nspname = $1 AND c.relkind IN ('r', 'p')", [schema]).values.to_h { |n, r| [n, r.to_i] }
    end

    def describe(name)
      rel = c.exec_params("SELECT c.oid, c.relkind, obj_description(c.oid, 'pg_class') FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace " \
                          "WHERE n.nspname = $1 AND c.relname = $2 AND c.relkind IN ('r', 'p', 'v', 'm', 'f')", [schema, name]).values.first
      return nil unless rel
      raise Error, t(:error_db_mig_view, name: name) unless %w(r p).include?(rel[1])
      oid = rel[0]
      cols = c.exec_params(<<~SQL, [oid]).to_a
        SELECT a.attname AS name, format_type(a.atttypid, a.atttypmod) AS type, a.attnotnull AS nn, pg_get_expr(d.adbin, d.adrelid) AS def,
               a.attidentity AS ident, a.attgenerated AS gen, col_description(a.attrelid, a.attnum) AS cmt
        FROM pg_attribute a LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
        WHERE a.attrelid = $1 AND a.attnum > 0 AND NOT a.attisdropped ORDER BY a.attnum
      SQL
      cons = c.exec_params(<<~SQL, [oid]).to_a
        SELECT con.conname AS name, con.contype AS type, pg_get_constraintdef(con.oid) AS def, rc.relname AS rtable,
               array_to_string(ARRAY(SELECT att.attname FROM unnest(con.conkey) WITH ORDINALITY k(n, o)
                 JOIN pg_attribute att ON att.attrelid = con.conrelid AND att.attnum = k.n ORDER BY k.o), E'\\x1f') AS cols
        FROM pg_constraint con LEFT JOIN pg_class rc ON rc.oid = con.confrelid
        WHERE con.conrelid = $1 AND con.contype IN ('p', 'u', 'f', 'c', 'x') ORDER BY con.conname
      SQL
      idx = c.exec_params(<<~SQL, [oid]).to_a
        SELECT i.relname AS name, pg_get_indexdef(ix.indexrelid) AS def FROM pg_index ix JOIN pg_class i ON i.oid = ix.indexrelid
        WHERE ix.indrelid = $1 AND NOT EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conindid = ix.indexrelid AND k.conrelid = ix.indrelid)
        ORDER BY i.relname
      SQL
      m = { columns: {}, order: [], pk: nil, cons: {}, fks: {}, indexes: {}, comment: rel[2], parents: [], uniques: [] }
      cols.each do |r|
        m[:order] << r['name']
        m[:columns][r['name']] = { name: r['name'], type: r['type'], notnull: r['nn'] == 't', default: r['def'],
                                   ident: r['ident'].to_s, gen: r['gen'].to_s, comment: r['cmt'] }
      end
      cons.each do |r|
        cl = r['cols'].to_s.split("\x1f")
        case r['type']
        when 'p' then m[:pk] = { name: r['name'], def: r['def'], cols: cl }
        when 'f'
          m[:fks][r['name']] = r['def']
          m[:parents] << r['rtable'] if r['rtable']
        else
          m[:cons][r['name']] = r['def']
          m[:uniques] << cl if r['type'] == 'u'
        end
      end
      # pg_get_indexdef 는 테이블 이름에 스키마를 붙이므로 떼어 냄 (대상은 search_path 로)
      sch = /\sON (ONLY )?(?:#{Regexp.escape(q(schema))}|#{Regexp.escape(schema)})\./
      idx.each { |r| m[:indexes][r['name']] = r['def'].sub(sch) { " ON #{Regexp.last_match(1)}" } }
      m
    end

    def coldef(col)
      s = +"#{q(col[:name])} #{col[:type]}"
      if col[:gen] == 's'
        s << " GENERATED ALWAYS AS (#{col[:default]}) STORED"
      elsif col[:ident].present?
        s << " GENERATED #{col[:ident] == 'a' ? 'ALWAYS' : 'BY DEFAULT'} AS IDENTITY"
      elsif col[:default]
        s << " DEFAULT #{col[:default]}"
      end
      s << ' NOT NULL' if col[:notnull]
      s
    end

    def seq_of(col)
      col[:default].to_s[/\Anextval\('((?:[^']|'')+)'::regclass\)/, 1]&.gsub("''", "'")
    end

    def comment_sql(name, col, text)
      target = col ? "COLUMN #{q(name)}.#{q(col)}" : "TABLE #{q(name)}"
      "COMMENT ON #{target} IS #{text.nil? ? 'NULL' : c.escape_literal(text)}"
    end

    def plan(name, a, b)
      unique = a[:pk].present? || a[:uniques].any?
      pre = a[:order].filter_map { |n| seq_of(a[:columns][n]) }.uniq.map { |sq| "CREATE SEQUENCE IF NOT EXISTS #{sq}" }
      if b.nil?
        body = a[:order].map { |n| coldef(a[:columns][n]) }
        body << "CONSTRAINT #{q(a[:pk][:name])} #{a[:pk][:def]}" if a[:pk]
        a[:cons].each { |n, d| body << "CONSTRAINT #{q(n)} #{d}" }
        st = pre + ["CREATE TABLE #{q(name)} (\n  #{body.join(",\n  ")}\n)"]
        st += a[:fks].map { |n, d| "ALTER TABLE #{q(name)} ADD CONSTRAINT #{q(n)} #{d}" }
        st += a[:indexes].values
        st << comment_sql(name, nil, a[:comment]) if a[:comment]
        a[:order].each { |n| st << comment_sql(name, n, a[:columns][n][:comment]) if a[:columns][n][:comment] }
        return { status: 'new', statements: st, warnings: [], unique: unique }
      end
      st = []
      warnings = []
      a[:order].each do |n|
        x = a[:columns][n]
        y = b[:columns][n]
        if y.nil?
          st << "ALTER TABLE #{q(name)} ADD COLUMN #{coldef(x)}"
          st << comment_sql(name, n, x[:comment]) if x[:comment]
          next
        end
        if x[:gen] != y[:gen] || x[:ident] != y[:ident] || (x[:gen] == 's' && x[:default] != y[:default])
          warnings << t(:text_db_mig_col_kind, name: n)
          next
        end
        st << "ALTER TABLE #{q(name)} ALTER COLUMN #{q(n)} TYPE #{x[:type]} USING #{q(n)}::#{x[:type]}" if x[:type] != y[:type]
        if x[:gen] != 's' && x[:ident].blank? && x[:default] != y[:default]
          st << (x[:default] ? "ALTER TABLE #{q(name)} ALTER COLUMN #{q(n)} SET DEFAULT #{x[:default]}" : "ALTER TABLE #{q(name)} ALTER COLUMN #{q(n)} DROP DEFAULT")
        end
        st << "ALTER TABLE #{q(name)} ALTER COLUMN #{q(n)} #{x[:notnull] ? 'SET' : 'DROP'} NOT NULL" if x[:notnull] != y[:notnull]
        st << comment_sql(name, n, x[:comment]) if x[:comment] != y[:comment]
      end
      (b[:order] - a[:order]).each { |n| warnings << t(:text_db_mig_keep_col, name: n) }
      if a[:pk]&.dig(:def) != b[:pk]&.dig(:def)
        if b[:pk].nil?
          st << "ALTER TABLE #{q(name)} ADD CONSTRAINT #{q(a[:pk][:name])} #{a[:pk][:def]}"
        else
          warnings << t(:text_db_mig_pk_diff)
        end
      end
      %i[cons fks].each do |k|
        a[k].each do |n, d|
          next if b[k][n] == d
          st << "ALTER TABLE #{q(name)} DROP CONSTRAINT #{q(n)}" if b[k][n]
          st << "ALTER TABLE #{q(name)} ADD CONSTRAINT #{q(n)} #{d}"
        end
      end
      a[:indexes].each do |n, d|
        next if b[:indexes][n] == d
        st << "DROP INDEX #{q(n)}" if b[:indexes][n]
        st << d
      end
      (b[:indexes].keys - a[:indexes].keys).each { |n| warnings << t(:text_db_mig_keep_index, name: n) }
      st << comment_sql(name, nil, a[:comment]) if a[:comment] != b[:comment]
      st = pre + st if st.any?
      unique ||= b[:pk].present? || b[:uniques].any?
      { status: st.any? ? 'changed' : 'same', statements: st, warnings: warnings, unique: unique }
    end

    def data_cols(m)
      m[:order].reject { |n| m[:columns][n][:gen] == 's' }
    end

    def copy_from(src, name, mode, sm, tm)
      cols = data_cols(sm) & data_cols(tm)
      raise Error, t(:error_db_mig_no_cols) if cols.empty?
      list = cols.map { |x| q(x) }.join(', ')
      key = tm[:pk] ? tm[:pk][:cols] : tm[:uniques].first
      key = nil unless key && (key - cols).empty?
      over = cols.any? { |n| tm[:columns][n][:ident] == 'a' } ? ' OVERRIDING SYSTEM VALUE' : ''
      rest = cols - (key || [])
      set = rest.any? ? "DO UPDATE SET #{rest.map { |x| "#{q(x)} = EXCLUDED.#{q(x)}" }.join(', ')}" : 'DO NOTHING'
      n = 0
      c.exec('BEGIN')
      c.exec("CREATE TEMP TABLE mig_tmp ON COMMIT DROP AS SELECT #{list} FROM #{q(name)} WITH NO DATA")
      src.c.copy_data("COPY #{q(name)} (#{list}) TO STDOUT") do
        c.copy_data("COPY mig_tmp (#{list}) FROM STDIN") do
          while (row = src.c.get_copy_data)
            c.put_copy_data(row)
            n += 1
            yield n if (n % 10_000).zero?
          end
        end
      end
      ins = "INSERT INTO #{q(name)} (#{list})#{over} SELECT #{list} FROM mig_tmp"
      case mode
      when 'replace'
        if key
          c.exec("DELETE FROM #{q(name)} d WHERE NOT EXISTS (SELECT 1 FROM mig_tmp s WHERE #{key.map { |x| "s.#{q(x)} = d.#{q(x)}" }.join(' AND ')})")
          c.exec("#{ins} ON CONFLICT (#{key.map { |x| q(x) }.join(', ')}) #{set}")
        else
          c.exec("DELETE FROM #{q(name)}")
          c.exec(ins)
        end
      when 'upsert'
        c.exec("#{ins} ON CONFLICT (#{key.map { |x| q(x) }.join(', ')}) #{set}")
      else
        c.exec("#{ins} ON CONFLICT DO NOTHING")
      end
      c.exec('COMMIT')
      reset_sequences(name, tm)
      n
    rescue StandardError
      begin
        c.exec('ROLLBACK')
      rescue StandardError
        nil
      end
      raise
    end

    # IDENTITY·nextval 칼럼의 시퀀스를 최대값 다음으로
    def reset_sequences(name, m)
      m[:order].each do |n|
        col = m[:columns][n]
        seq = col[:ident].present? ? c.exec_params('SELECT pg_get_serial_sequence($1, $2)', ["#{q(schema)}.#{q(name)}", n]).getvalue(0, 0) : seq_of(col)
        next unless seq
        c.exec("SELECT setval(#{c.escape_literal(seq)}, COALESCE((SELECT MAX(#{q(n)}) FROM #{q(name)}), 0) + 1, false)")
      end
    end

    def backup(name, m, gz)
      gz.write("-- #{name} 이관 전 백업 (#{Time.current.in_time_zone('Asia/Seoul').strftime('%F %T')}) — psql 로 실행\n")
      gz.write("SET client_encoding = 'UTF8';\nSET search_path TO #{q(schema)};\nSET DateStyle = 'ISO, YMD';\nSET TIME ZONE 'UTC';\nBEGIN;\n")
      # 복원하는 때 이 테이블을 참조하는 다른 테이블의 외래키를 저장 → CASCADE 로 지워진 뒤 끝에 다시 만듦 (NOT VALID)
      reg = c.escape_literal("#{q(schema)}.#{q(name)}")
      gz.write("CREATE TEMP TABLE mig_fk ON COMMIT DROP AS SELECT conrelid::regclass::text AS tbl, conname, pg_get_constraintdef(oid) AS def " \
               "FROM pg_constraint WHERE contype = 'f' AND confrelid = to_regclass(#{reg}) AND conrelid <> confrelid;\n")
      gz.write("DROP TABLE IF EXISTS #{q(name)} CASCADE;\n")
      plan(name, m, nil)[:statements].each { |s| gz.write("#{s};\n") unless s.start_with?('ALTER TABLE') || s.start_with?('CREATE INDEX') || s.start_with?('CREATE UNIQUE INDEX') }
      cols = data_cols(m)
      list = cols.map { |x| q(x) }.join(', ')
      over = cols.any? { |n| m[:columns][n][:ident] == 'a' }
      # IDENTITY ALWAYS 칼럼에 값을 넣으려면 잠시 BY DEFAULT 로
      cols.each { |n| gz.write("ALTER TABLE #{q(name)} ALTER COLUMN #{q(n)} SET GENERATED BY DEFAULT;\n") if m[:columns][n][:ident] == 'a' } if over
      gz.write("COPY #{q(name)} (#{list}) FROM stdin;\n")
      n = 0
      c.copy_data("COPY #{q(name)} (#{list}) TO STDOUT") do
        while (row = c.get_copy_data)
          gz.write(row)
          n += 1
        end
      end
      gz.write("\\.\n")
      cols.each { |x| gz.write("ALTER TABLE #{q(name)} ALTER COLUMN #{q(x)} SET GENERATED ALWAYS;\n") if m[:columns][x][:ident] == 'a' } if over
      plan(name, m, nil)[:statements].each { |s| gz.write("#{s};\n") if s.start_with?('ALTER TABLE') || s.start_with?('CREATE INDEX') || s.start_with?('CREATE UNIQUE INDEX') }
      gz.write("DO $$ DECLARE r record; BEGIN FOR r IN SELECT * FROM mig_fk LOOP " \
               "EXECUTE format('ALTER TABLE %s ADD CONSTRAINT %I %s NOT VALID', r.tbl, r.conname, r.def); END LOOP; END $$;\n")
      gz.write("COMMIT;\n")
      n
    end
  end
end
