# 이관 엔진 — Oracle (ruby-oci8)
# - 구조: all_tab_cols(가상 칼럼 포함)·all_tab_identity_cols·all_constraints·all_cons_columns·all_indexes·주석 → CREATE / ALTER (MODIFY 는 바뀐 속성만)
#   두 세션 CURRENT_SCHEMA 를 각 스키마로, 시스템 이름(SYS_C…) 제약은 이름 없이 만듦. 함수 기반 인덱스·LONG·XMLTYPE 등은 알림만
# - 데이터: 원본에서 TO_CHAR 등으로 문자열로 읽고(날짜·TIMESTAMP 는 형식 고정, RAW 는 16진) 대상에서 TO_DATE·HEXTORAW 로 되돌려 넣음
#   LOB 없는 테이블은 500행씩 배열 바인드, LOB 가 있으면 한 행씩. upsert·insert_new 는 MERGE
#   IDENTITY ALWAYS 칼럼은 잠시 BY DEFAULT 로, 끝나면 START WITH LIMIT VALUE. 이 테이블의 외래키와 이 테이블을 참조하는 외래키는 잠시 DISABLE 후 ENABLE NOVALIDATE
# - 백업: DROP + CREATE + INSERT 스크립트 (SQLcl·SQL*Plus 로 실행, 큰 BLOB 는 PL/SQL 블록)
module DbManage
  class MigrateOracle < MigrateBase
    ARRAY = 500
    LOB = %w(CLOB NCLOB BLOB).freeze
    UNSUPPORTED = /\A(LONG|LONG RAW|XMLTYPE|SDO_|ANYDATA|BFILE|UROWID|ROWID)/
    TS = 'YYYY-MM-DD HH24:MI:SS.FF9'.freeze
    TSZ = 'YYYY-MM-DD HH24:MI:SS.FF9 TZH:TZM'.freeze
    DT = 'YYYY-MM-DD HH24:MI:SS'.freeze

    def q(name)
      %("#{name.to_s.gsub('"', '""')}")
    end

    def s(v)
      "'#{v.to_s.gsub("'", "''")}'"
    end

    def exec(sql)
      c.exec(sql)
    end

    def rows(sql, *binds)
      cur = c.parse(sql)
      binds.each_with_index { |b, i| cur.bind_param(i + 1, b) }
      cur.exec
      names = cur.get_col_names.map(&:downcase)
      list = []
      while (r = cur.fetch)
        list << names.zip(r.map { |v| v.respond_to?(:read) ? v.read : v }).to_h
      end
      list
    ensure
      cur&.close
    end

    def prepare
      exec("ALTER SESSION SET CURRENT_SCHEMA = #{q(schema)}")
      exec("ALTER SESSION SET NLS_NUMERIC_CHARACTERS = '.,'")
      exec("ALTER SESSION SET TIME_ZONE = '+00:00'")
    end

    def count(name)
      rows("SELECT COUNT(*) AS n FROM #{q(name)}").first['n'].to_i
    end

    def row_estimates
      rows('SELECT table_name, num_rows FROM all_tables WHERE owner = :1', schema).to_h { |r| [r['table_name'], r['num_rows']&.to_i] }
    end

    def describe(name)
      kind = rows("SELECT object_type FROM all_objects WHERE owner = :1 AND object_name = :2 AND object_type IN ('TABLE', 'VIEW', 'MATERIALIZED VIEW')", schema, name).map { |r| r['object_type'] }
      return nil if kind.empty?
      raise Error, t(:error_db_mig_view, name: name) unless kind.include?('TABLE') && !kind.include?('MATERIALIZED VIEW')
      m = { columns: {}, order: [], pk: nil, cons: {}, fks: {}, indexes: {}, parents: [], uniques: [], warnings: [],
            comment: rows('SELECT comments FROM all_tab_comments WHERE owner = :1 AND table_name = :2', schema, name).first&.dig('comments') }
      idents = rows('SELECT column_name, generation_type FROM all_tab_identity_cols WHERE owner = :1 AND table_name = :2', schema, name)
               .to_h { |r| [r['column_name'], r['generation_type']] }
      rows(<<~SQL, schema, name).each do |r|
        SELECT tc.column_name, tc.data_type, tc.data_length, tc.char_length, tc.char_used, tc.data_precision, tc.data_scale, tc.nullable,
               tc.data_default, tc.virtual_column, cc.comments
        FROM all_tab_cols tc LEFT JOIN all_col_comments cc ON cc.owner = tc.owner AND cc.table_name = tc.table_name AND cc.column_name = tc.column_name
        WHERE tc.owner = :1 AND tc.table_name = :2 AND tc.hidden_column = 'NO' ORDER BY tc.column_id
      SQL
        n = r['column_name']
        m[:order] << n
        m[:columns][n] = { name: n, dtype: r['data_type'], type: type_of(r), notnull: r['nullable'] == 'N', virtual: r['virtual_column'] == 'YES',
                           default: r['data_default'].to_s.strip.presence, ident: idents[n], comment: r['comments'] }
        m[:warnings] << t(:text_db_mig_unsupported_col, name: n, type: r['data_type']) if r['data_type'].match?(UNSUPPORTED)
      end
      cons = rows(<<~SQL, schema, name)
        SELECT c.constraint_name, c.constraint_type, c.generated, c.delete_rule, c.search_condition_vc, r.table_name AS rtable, r.owner AS rowner,
               (SELECT LISTAGG('"' || cc.column_name || '"', ',') WITHIN GROUP (ORDER BY cc.position) FROM all_cons_columns cc
                 WHERE cc.owner = c.owner AND cc.constraint_name = c.constraint_name) AS cols,
               (SELECT LISTAGG('"' || rc.column_name || '"', ',') WITHIN GROUP (ORDER BY rc.position) FROM all_cons_columns rc
                 WHERE rc.owner = c.r_owner AND rc.constraint_name = c.r_constraint_name) AS rcols
        FROM all_constraints c LEFT JOIN all_constraints r ON r.owner = c.r_owner AND r.constraint_name = c.r_constraint_name
        WHERE c.owner = :1 AND c.table_name = :2 AND c.constraint_type IN ('P', 'U', 'R', 'C')
      SQL
      cons.each do |r|
        user_named = r['generated'] == 'USER NAME'
        prefix = user_named ? "CONSTRAINT #{q(r['constraint_name'])} " : ''
        cl = r['cols'].to_s.split(',').map { |x| x.delete('"') }
        case r['constraint_type']
        when 'P' then m[:pk] = { name: r['constraint_name'], def: "#{prefix}PRIMARY KEY (#{r['cols']})", cols: cl, named: user_named }
        when 'U'
          m[:cons][user_named ? r['constraint_name'] : "U:#{r['cols']}"] = "#{prefix}UNIQUE (#{r['cols']})"
          m[:uniques] << cl
        when 'R'
          rt = r['rowner'] == schema ? q(r['rtable']) : "#{q(r['rowner'])}.#{q(r['rtable'])}"
          del = { 'CASCADE' => ' ON DELETE CASCADE', 'SET NULL' => ' ON DELETE SET NULL' }[r['delete_rule']].to_s
          m[:fks][user_named ? r['constraint_name'] : "R:#{r['cols']}"] = "#{prefix}FOREIGN KEY (#{r['cols']}) REFERENCES #{rt} (#{r['rcols']})#{del}"
          m[:parents] << r['rtable'] if r['rowner'] == schema
        when 'C'
          next unless user_named && r['search_condition_vc']
          m[:cons][r['constraint_name']] = "#{prefix}CHECK (#{r['search_condition_vc']})"
        end
      end
      rows(<<~SQL, schema, name).each do |r|
        SELECT i.index_name, i.uniqueness, i.index_type,
               (SELECT LISTAGG('"' || ic.column_name || '"' || DECODE(ic.descend, 'DESC', ' DESC', ''), ',') WITHIN GROUP (ORDER BY ic.column_position)
                 FROM all_ind_columns ic WHERE ic.index_owner = i.owner AND ic.index_name = i.index_name) AS cols
        FROM all_indexes i WHERE i.table_owner = :1 AND i.table_name = :2 AND i.index_type NOT LIKE 'LOB%'
          AND NOT EXISTS (SELECT 1 FROM all_constraints k WHERE k.owner = i.table_owner AND k.index_name = i.index_name AND k.constraint_type IN ('P', 'U'))
      SQL
        if r['index_type'].start_with?('FUNCTION-BASED')
          m[:warnings] << t(:text_db_mig_fn_index, name: r['index_name'])
          next
        end
        m[:indexes][r['index_name']] = "CREATE #{'UNIQUE ' if r['uniqueness'] == 'UNIQUE'}INDEX #{q(r['index_name'])} ON #{q(name)} (#{r['cols']})"
        m[:uniques] << r['cols'].split(',').map { |x| x.delete('"') } if r['uniqueness'] == 'UNIQUE'
      end
      m
    end

    def type_of(r)
      dt = r['data_type']
      case dt
      when 'VARCHAR2', 'CHAR' then r['char_used'] == 'C' ? "#{dt}(#{r['char_length'].to_i} CHAR)" : "#{dt}(#{r['data_length'].to_i} BYTE)"
      when 'NVARCHAR2', 'NCHAR' then "#{dt}(#{r['char_length'].to_i})"
      when 'NUMBER'
        p = r['data_precision']
        sc = r['data_scale']
        if p then sc.to_i.zero? ? "NUMBER(#{p.to_i})" : "NUMBER(#{p.to_i},#{sc.to_i})"
        else sc && sc.to_i.zero? ? 'NUMBER(*,0)' : 'NUMBER'
        end
      when 'FLOAT' then "FLOAT(#{r['data_precision'].to_i})"
      when 'RAW' then "RAW(#{r['data_length'].to_i})"
      else dt
      end
    end

    def coldef(col, ident: col[:ident])
      d = +"#{q(col[:name])} #{col[:type]}"
      if col[:virtual]
        d << " GENERATED ALWAYS AS (#{col[:default]}) VIRTUAL"
        return d
      end
      if ident
        d << " GENERATED #{ident} AS IDENTITY"
      elsif col[:default]
        d << " DEFAULT #{col[:default]}"
      end
      d << ' NOT NULL' if col[:notnull]
      d
    end

    def comment_sql(name, col, text)
      "COMMENT ON #{col ? "COLUMN #{q(name)}.#{q(col)}" : "TABLE #{q(name)}"} IS #{s(text.to_s)}"
    end

    def plan(name, a, b)
      unique = a[:pk].present? || a[:uniques].any?
      warnings = a[:warnings].dup
      if b.nil?
        body = a[:order].map { |n| coldef(a[:columns][n]) }
        body << a[:pk][:def] if a[:pk]
        body += a[:cons].values
        st = ["CREATE TABLE #{q(name)} (\n  #{body.join(",\n  ")}\n)"]
        st += a[:fks].values.map { |d| "ALTER TABLE #{q(name)} ADD #{d}" }
        st += a[:indexes].values
        st << comment_sql(name, nil, a[:comment]) if a[:comment]
        a[:order].each { |n| st << comment_sql(name, n, a[:columns][n][:comment]) if a[:columns][n][:comment] }
        return { status: 'new', statements: st, warnings: warnings, unique: unique }
      end
      st = []
      a[:order].each do |n|
        x = a[:columns][n]
        y = b[:columns][n]
        if y.nil?
          st << "ALTER TABLE #{q(name)} ADD (#{coldef(x)})"
          st << comment_sql(name, n, x[:comment]) if x[:comment]
          next
        end
        if x[:virtual] != y[:virtual] || x[:ident].nil? != y[:ident].nil? || (x[:virtual] && x[:default] != y[:default])
          warnings << t(:text_db_mig_col_kind, name: n)
          next
        end
        next if x[:virtual]
        st << "ALTER TABLE #{q(name)} MODIFY (#{q(n)} #{x[:type]})" if x[:type] != y[:type]
        st << "ALTER TABLE #{q(name)} MODIFY (#{q(n)} DEFAULT #{x[:default] || 'NULL'})" if x[:ident].nil? && x[:default] != y[:default]
        st << "ALTER TABLE #{q(name)} MODIFY (#{q(n)} #{x[:notnull] ? 'NOT NULL' : 'NULL'})" if x[:notnull] != y[:notnull]
        st << comment_sql(name, n, x[:comment]) if x[:comment] != y[:comment]
      end
      (b[:order] - a[:order]).each { |n| warnings << t(:text_db_mig_keep_col, name: n) }
      if a[:pk]&.dig(:cols) != b[:pk]&.dig(:cols)
        if b[:pk].nil?
          st << "ALTER TABLE #{q(name)} ADD #{a[:pk][:def]}"
        else
          warnings << t(:text_db_mig_pk_diff)
        end
      end
      %i[cons fks].each do |k|
        a[k].each do |n, d|
          next if b[k][n] == d || b[k].value?(d)
          st << "ALTER TABLE #{q(name)} DROP CONSTRAINT #{q(n)}" if b[k][n] && !n.include?(':')
          st << "ALTER TABLE #{q(name)} ADD #{d}"
        end
      end
      a[:indexes].each do |n, d|
        next if b[:indexes][n] == d
        st << "DROP INDEX #{q(n)}" if b[:indexes][n]
        st << d
      end
      (b[:indexes].keys - a[:indexes].keys).each { |n| warnings << t(:text_db_mig_keep_index, name: n) }
      st << comment_sql(name, nil, a[:comment]) if a[:comment] != b[:comment]
      unique ||= b[:pk].present? || b[:uniques].any?
      { status: st.any? ? 'changed' : 'same', statements: st, warnings: warnings.uniq, unique: unique }
    end

    def data_cols(m)
      m[:order].reject { |n| m[:columns][n][:virtual] || m[:columns][n][:dtype].match?(UNSUPPORTED) }
    end

    # 원본 칼럼을 문자열로 읽는 식 / 대상에 넣는 식(:n 자리)
    def sel(col)
      x = q(col[:name])
      case col[:dtype]
      when 'DATE' then "TO_CHAR(#{x}, '#{DT}')"
      when /WITH TIME ZONE\z/ then col[:dtype].include?('LOCAL') ? "TO_CHAR(#{x}, '#{TS}')" : "TO_CHAR(#{x}, '#{TSZ}')"
      when /\ATIMESTAMP/ then "TO_CHAR(#{x}, '#{TS}')"
      when 'NUMBER', 'FLOAT' then "TO_CHAR(#{x}, 'TM9')"
      when 'BINARY_FLOAT', 'BINARY_DOUBLE', /\AINTERVAL/ then "TO_CHAR(#{x})"
      when 'RAW' then "RAWTOHEX(#{x})"
      else x
      end
    end

    def ins(col, bind)
      case col[:dtype]
      when 'DATE' then "TO_DATE(#{bind}, '#{DT}')"
      when /WITH TIME ZONE\z/ then col[:dtype].include?('LOCAL') ? "TO_TIMESTAMP(#{bind}, '#{TS}')" : "TO_TIMESTAMP_TZ(#{bind}, '#{TSZ}')"
      when /\ATIMESTAMP/ then "TO_TIMESTAMP(#{bind}, '#{TS}')"
      when 'NUMBER', 'FLOAT' then "TO_NUMBER(#{bind})"
      when 'BINARY_FLOAT' then "TO_BINARY_FLOAT(#{bind})"
      when 'BINARY_DOUBLE' then "TO_BINARY_DOUBLE(#{bind})"
      when /\AINTERVAL YEAR/ then "TO_YMINTERVAL(#{bind})"
      when /\AINTERVAL DAY/ then "TO_DSINTERVAL(#{bind})"
      when 'RAW' then "HEXTORAW(#{bind})"
      else bind
      end
    end

    # 원본에서 행마다 [문자열|nil ...] (LOB 은 읽은 값)
    def each_source_row(src, name, cols, m)
      cur = src.c.parse("SELECT #{cols.map { |x| sel(m[:columns][x]) }.join(', ')} FROM #{q(name)}")
      cur.prefetch_rows = 500
      cur.exec
      while (r = cur.fetch)
        yield(r.map do |v|
          v = v.read if v.respond_to?(:read)
          v.is_a?(String) && v.encoding != Encoding::BINARY ? v.dup.force_encoding('UTF-8') : v
        end)
      end
    ensure
      cur&.close
    end

    # 이 테이블의 외래키 + 이 테이블을 참조하는 외래키 [테이블, 제약 이름]
    def related_fks(name)
      rows(<<~SQL, schema, name, schema, name).map { |r| [r['owner'], r['table_name'], r['constraint_name']] }
        SELECT owner, table_name, constraint_name FROM all_constraints WHERE constraint_type = 'R' AND status = 'ENABLED' AND owner = :1 AND table_name = :2
        UNION
        SELECT f.owner, f.table_name, f.constraint_name FROM all_constraints f JOIN all_constraints p ON p.owner = f.r_owner AND p.constraint_name = f.r_constraint_name
        WHERE f.constraint_type = 'R' AND f.status = 'ENABLED' AND p.owner = :3 AND p.table_name = :4
      SQL
    end

    def copy_from(src, name, mode, sm, tm)
      cols = data_cols(sm) & data_cols(tm)
      raise Error, t(:error_db_mig_no_cols) if cols.empty?
      tcol = cols.map { |x| tm[:columns][x] }
      lob = tcol.map { |x| LOB.include?(x[:dtype]) ? { 'CLOB' => OCI8::CLOB, 'NCLOB' => OCI8::NCLOB, 'BLOB' => OCI8::BLOB }[x[:dtype]] : nil }
      key = tm[:pk] ? tm[:pk][:cols] : tm[:uniques].first
      key = nil unless key && (key - cols).empty?
      rest = cols - (key || [])
      list = cols.map { |x| q(x) }.join(', ')
      sql = if mode == 'replace' || (mode == 'insert_new' && key.nil?)
              "INSERT INTO #{q(name)} (#{list}) VALUES (#{tcol.each_with_index.map { |x, i| ins(x, ":#{i + 1}") }.join(', ')})"
            else
              srcsel = tcol.each_with_index.map { |x, i| "#{ins(x, ":#{i + 1}")} AS #{q(x[:name])}" }.join(', ')
              upd = mode == 'upsert' && rest.any? ? " WHEN MATCHED THEN UPDATE SET #{rest.map { |x| "T.#{q(x)} = S.#{q(x)}" }.join(', ')}" : ''
              "MERGE INTO #{q(name)} T USING (SELECT #{srcsel} FROM dual) S ON (#{key.map { |x| "T.#{q(x)} = S.#{q(x)}" }.join(' AND ')})#{upd} " \
                "WHEN NOT MATCHED THEN INSERT (#{list}) VALUES (#{cols.map { |x| "S.#{q(x)}" }.join(', ')})"
            end
      always = cols.select { |x| tm[:columns][x][:ident] == 'ALWAYS' }
      idents = cols.select { |x| tm[:columns][x][:ident] }
      fks = related_fks(name)
      # DDL 은 자동 커밋되므로 트랜잭션 밖에서: 외래키 끄기 · IDENTITY ALWAYS → BY DEFAULT
      fks.each { |o, tb, cn| exec("ALTER TABLE #{q(o)}.#{q(tb)} DISABLE CONSTRAINT #{q(cn)}") }
      always.each { |x| exec("ALTER TABLE #{q(name)} MODIFY (#{q(x)} GENERATED BY DEFAULT AS IDENTITY)") }
      n = 0
      begin
        exec("DELETE FROM #{q(name)}") if mode == 'replace'
        batch = []
        flush = lambda do
          return if batch.empty?
          if lob.any?
            cur = c.parse(sql)
            batch.each do |row|
              row.each_with_index do |v, i|
                if lob[i]
                  cur.bind_param(i + 1, v.nil? ? nil : lob[i].new(c, v), lob[i])
                else
                  cur.bind_param(i + 1, v, String, [v.to_s.bytesize, 1].max)
                end
              end
              cur.exec
            end
            cur.close
          else
            cur = c.parse(sql)
            cur.max_array_size = batch.size
            cols.each_index do |i|
              vals = batch.map { |r| r[i] }
              cur.bind_param_array(i + 1, vals, String, [vals.map { |v| v.to_s.bytesize }.max.to_i, 1].max)
            end
            cur.exec_array
            cur.close
          end
          n += batch.size
          batch.clear
          yield n
        end
        size = lob.any? ? 100 : ARRAY
        drain(->(&blk) { each_source_row(src, name, cols, sm, &blk) }) do |row|
          batch << row
          flush.call if batch.size >= size
        end
        flush.call
        c.commit
      rescue StandardError
        c.rollback
        raise
      ensure
        always.each { |x| safe_exec("ALTER TABLE #{q(name)} MODIFY (#{q(x)} GENERATED ALWAYS AS IDENTITY)") }
        idents.each { |x| safe_exec("ALTER TABLE #{q(name)} MODIFY (#{q(x)} GENERATED #{tm[:columns][x][:ident]} AS IDENTITY (START WITH LIMIT VALUE))") }
        fks.each { |o, tb, cn| safe_exec("ALTER TABLE #{q(o)}.#{q(tb)} ENABLE NOVALIDATE CONSTRAINT #{q(cn)}") }
      end
      n
    end

    def safe_exec(sql)
      exec(sql)
    rescue StandardError => e
      Rails.logger.warn("[db_migrate] #{sql}: #{e.message}")
    end

    # 백업 스크립트용 리터럴 (문자열은 1000자씩 끊어 TO_CLOB 연결)
    def lit(col, v)
      return 'NULL' if v.nil?
      case col[:dtype]
      when 'BLOB' then v.bytesize <= 2000 ? "TO_BLOB(HEXTORAW('#{v.unpack1('H*')}'))" : 'EMPTY_BLOB()'
      when 'CLOB', 'NCLOB'
        v.empty? ? 'EMPTY_CLOB()' : v.scan(/.{1,1000}/m).map { |x| "TO_#{col[:dtype]}(#{s(x)})" }.join(' || ')
      when 'VARCHAR2', 'CHAR', 'NVARCHAR2', 'NCHAR' then col[:dtype].start_with?('N') ? "N#{s(v)}" : s(v)
      else ins(col, s(v))
      end
    end

    def backup(name, m, gz)
      gz.write("-- #{name} 이관 전 백업 (#{Time.current.in_time_zone('Asia/Seoul').strftime('%F %T')}) — SQLcl·SQL*Plus 로 실행\n")
      gz.write("SET DEFINE OFF\nALTER SESSION SET CURRENT_SCHEMA = #{q(schema)};\nALTER SESSION SET NLS_NUMERIC_CHARACTERS = '.,';\nALTER SESSION SET TIME_ZONE = '+00:00';\n")
      # 복원하는 때 이 테이블을 참조하는 외래키 정의를 MIG_RESTORE_FK 에 저장 → CASCADE CONSTRAINTS 로 지워진 뒤 끝에 다시 만들고 표는 지움
      qn = q(name).gsub("'", "''")
      gz.write("BEGIN EXECUTE IMMEDIATE 'DROP TABLE MIG_RESTORE_FK PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;\n/\n")
      gz.write("CREATE TABLE MIG_RESTORE_FK AS SELECT 'ALTER TABLE \"' || f.owner || '\".\"' || f.table_name || '\" ADD CONSTRAINT \"' || f.constraint_name || '\" FOREIGN KEY (' || " \
               "(SELECT LISTAGG('\"' || cc.column_name || '\"', ',') WITHIN GROUP (ORDER BY cc.position) FROM all_cons_columns cc WHERE cc.owner = f.owner AND cc.constraint_name = f.constraint_name) || " \
               "') REFERENCES #{qn} (' || (SELECT LISTAGG('\"' || rc.column_name || '\"', ',') WITHIN GROUP (ORDER BY rc.position) FROM all_cons_columns rc " \
               "WHERE rc.owner = p.owner AND rc.constraint_name = p.constraint_name) || ')' || DECODE(f.delete_rule, 'CASCADE', ' ON DELETE CASCADE', 'SET NULL', ' ON DELETE SET NULL', '') || ' ENABLE NOVALIDATE' AS ddl " \
               "FROM all_constraints f JOIN all_constraints p ON p.owner = f.r_owner AND p.constraint_name = f.r_constraint_name " \
               "WHERE f.constraint_type = 'R' AND p.owner = #{s(schema)} AND p.table_name = #{s(name)} AND NOT (f.owner = p.owner AND f.table_name = p.table_name);\n")
      gz.write("BEGIN EXECUTE IMMEDIATE 'DROP TABLE #{qn} CASCADE CONSTRAINTS PURGE'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -942 THEN RAISE; END IF; END;\n/\n")
      # 값을 그대로 넣도록 IDENTITY 는 BY DEFAULT 로 만들고 끝에 원래대로
      plain = m.merge(columns: m[:columns].transform_values { |x| x[:ident] ? x.merge(ident: 'BY DEFAULT') : x })
      stmts = plan(name, plain, nil)[:statements]
      gz.write("#{stmts.first};\n")
      cols = data_cols(m)
      list = cols.map { |x| q(x) }.join(', ')
      blobs = cols.select { |x| m[:columns][x][:dtype] == 'BLOB' }
      n = 0
      each_source_row(self, name, cols, m) do |row|
        n += 1
        vals = cols.each_with_index.map { |x, i| lit(m[:columns][x], row[i]) }
        big = blobs.select { |x| (v = row[cols.index(x)]) && v.bytesize > 2000 }
        if big.empty?
          gz.write("INSERT INTO #{q(name)} (#{list}) VALUES (#{vals.join(', ')});\n")
        else
          decl = big.each_index.map { |i| "b#{i} BLOB;" }.join(' ')
          gz.write("DECLARE #{decl} BEGIN INSERT INTO #{q(name)} (#{list}) VALUES (#{vals.join(', ')}) RETURNING #{big.map { |x| q(x) }.join(', ')} INTO #{big.each_index.map { |i| "b#{i}" }.join(', ')};\n")
          big.each_with_index do |x, i|
            row[cols.index(x)].bytes.each_slice(2000) { |part| gz.write("DBMS_LOB.WRITEAPPEND(b#{i}, #{part.size}, HEXTORAW('#{part.pack('C*').unpack1('H*')}'));\n") }
          end
          gz.write("END;\n/\n")
        end
        gz.write("COMMIT;\n") if (n % 1000).zero?
      end
      gz.write("COMMIT;\n")
      m[:order].each do |x|
        id = m[:columns][x][:ident]
        gz.write("ALTER TABLE #{q(name)} MODIFY (#{q(x)} GENERATED #{id} AS IDENTITY (START WITH LIMIT VALUE));\n") if id
      end
      stmts.drop(1).each { |x| gz.write("#{x};\n") }
      gz.write("BEGIN FOR r IN (SELECT ddl FROM MIG_RESTORE_FK) LOOP EXECUTE IMMEDIATE r.ddl; END LOOP; EXECUTE IMMEDIATE 'DROP TABLE MIG_RESTORE_FK PURGE'; END;\n/\n")
      n
    end

    # ---- 뷰·구체화 뷰·함수·프로시저·패키지 ----
    OBJ_TYPES = { 'view' => 'VIEW', 'matview' => 'MATERIALIZED VIEW', 'function' => 'FUNCTION', 'procedure' => 'PROCEDURE', 'package' => 'PACKAGE' }.freeze

    def object_kinds
      OBJ_TYPES.keys
    end

    def object_exists?(kind, key)
      rows('SELECT 1 AS x FROM all_objects WHERE owner = :1 AND object_name = :2 AND object_type = :3', schema, key, OBJ_TYPES.fetch(kind)).any?
    end

    def source_text(type, key)
      rows('SELECT text FROM all_source WHERE owner = :1 AND name = :2 AND type = :3 ORDER BY line', schema, key, type).map { |r| r['text'] }.join.rstrip.presence
    end

    def rename_schema(text, to_schema)
      return text if to_schema == schema
      text.gsub(/"#{Regexp.escape(schema)}"\./, "#{q(to_schema)}.").gsub(/\b#{Regexp.escape(schema)}\./i, "#{q(to_schema)}.")
    end

    def object_ddl(kind, key, to_schema)
      st = case kind
           when 'view'
             v = rows('SELECT text FROM all_views WHERE owner = :1 AND view_name = :2', schema, key).first or raise Error, t(:error_db_mig_obj_def)
             cols = rows("SELECT column_name FROM all_tab_cols WHERE owner = :1 AND table_name = :2 AND hidden_column = 'NO' ORDER BY column_id", schema, key)
             ["CREATE OR REPLACE FORCE VIEW #{q(key)} (#{cols.map { |r| q(r['column_name']) }.join(', ')}) AS #{v['text'].to_s.strip}"]
           when 'matview'
             v = rows('SELECT query FROM all_mviews WHERE owner = :1 AND mview_name = :2', schema, key).first or raise Error, t(:error_db_mig_obj_def)
             ["BEGIN EXECUTE IMMEDIATE 'DROP MATERIALIZED VIEW #{q(key).gsub("'", "''")}'; EXCEPTION WHEN OTHERS THEN IF SQLCODE != -12003 THEN RAISE; END IF; END;",
              "CREATE MATERIALIZED VIEW #{q(key)} AS #{v['query'].to_s.strip}"]
           when 'package'
             spec = source_text('PACKAGE', key) or raise Error, t(:error_db_mig_obj_def)
             body = source_text('PACKAGE BODY', key)
             ["CREATE OR REPLACE #{spec}"] + (body ? ["CREATE OR REPLACE #{body}"] : [])
           else
             ["CREATE OR REPLACE #{source_text(OBJ_TYPES.fetch(kind), key) || raise(Error, t(:error_db_mig_obj_def))}"]
           end
      st.map { |x| rename_schema(x, to_schema) }
    end

    # 컴파일 오류(ORA-24344)로 만들어진 개체는 INVALID → 오류 내용을 올려 다음 차례에 다시 시도
    def create_object(kind, key, statements)
      statements.each do |x|
        exec(x)
      rescue OCIError => e
        raise unless e.code == 24_344
      end
      bad = rows("SELECT object_type FROM all_objects WHERE owner = :1 AND object_name = :2 AND status = 'INVALID'", schema, key)
      return if bad.empty? || kind == 'matview'
      errs = rows('SELECT type, line, position, text FROM all_errors WHERE owner = :1 AND name = :2 ORDER BY sequence', schema, key).first(3)
      raise Error, t(:error_db_mig_compile, msg: errs.map { |r| "#{r['type']} #{r['line']}:#{r['position']} #{r['text'].to_s.strip}" }.join(' / ').presence || 'INVALID')
    end

    def object_script(kind, key)
      return nil unless object_exists?(kind, key)
      st = object_ddl(kind, key, schema)
      "-- #{kind} #{key} 이관 전 백업 — SQLcl·SQL*Plus 로 실행\nSET DEFINE OFF\nALTER SESSION SET CURRENT_SCHEMA = #{q(schema)};\n" +
        st.map { |x| kind == 'view' || x.start_with?('CREATE MATERIALIZED') ? "#{x};\n" : "#{x}\n/\n" }.join
    end
  end
end
