# 이관 엔진 — MS SQL Server (tiny_tds)
# - 구조: sys.columns·types·identity·computed·default_constraints·indexes·foreign_keys·check_constraints·MS_Description → CREATE / ALTER
# - 데이터: 원본에서 칼럼마다 문자열로 바꿔 읽고(날짜 126 형식, float 3, money 2, 바이너리 0x… 16진) 대상에 1000행씩 INSERT/MERGE
#   IDENTITY 칼럼은 IDENTITY_INSERT, 계산 칼럼·rowversion 은 제외. 이 테이블과 이 테이블을 참조하는 외래키는 잠시 NOCHECK 후 다시 CHECK(검증 없이)
# - 백업: DROP + CREATE + INSERT 스크립트 (sqlcmd 로 실행하면 복원)
module DbManage
  class MigrateMssql < MigrateBase
    ROWS = 1000
    TEXTY = %w(char varchar nchar nvarchar text ntext xml sysname uniqueidentifier).freeze

    def q(name)
      "[#{name.to_s.gsub(']', ']]')}]"
    end

    def qt(name)
      "#{q(schema)}.#{q(name)}"
    end

    def s(v)
      "N'#{v.to_s.gsub("'", "''")}'"
    end

    def exec(sql)
      c.execute(sql).do
    end

    def rows(sql)
      res = c.execute(sql)
      list = res.each(as: :hash, cache_rows: true).map { |h| h.transform_values { |v| v.is_a?(String) ? v.dup.force_encoding('UTF-8').scrub : v } }
      res.cancel
      list
    end

    # 카탈로그의 FOR XML … .value() 와 계산 칼럼·필터 인덱스 테이블 쓰기에 필요한 세션 옵션 (조회 연결에도)
    def prepare
      exec('SET ANSI_NULLS ON; SET ANSI_PADDING ON; SET ANSI_WARNINGS ON; SET ARITHABORT ON; SET CONCAT_NULL_YIELDS_NULL ON; ' \
           'SET QUOTED_IDENTIFIER ON; SET NUMERIC_ROUNDABORT OFF; SET TEXTSIZE 2147483647')
      exec('SET XACT_ABORT ON') if @write
    end

    def count(name)
      rows("SELECT COUNT_BIG(*) AS n FROM #{qt(name)}").first['n'].to_i
    end

    def row_estimates
      rows("SELECT o.name AS n, SUM(p.rows) AS r FROM sys.objects o JOIN sys.schemas sc ON sc.schema_id = o.schema_id " \
           "JOIN sys.partitions p ON p.object_id = o.object_id AND p.index_id IN (0, 1) WHERE sc.name = #{s(schema)} AND o.type = 'U' GROUP BY o.name")
        .to_h { |r| [r['n'], r['r'].to_i] }
    end

    def keylist(oid, index_id, included)
      "STUFF((SELECT ',' + QUOTENAME(col.name)#{included ? '' : " + CASE WHEN ic.is_descending_key = 1 THEN ' DESC' ELSE '' END"} " \
        "FROM sys.index_columns ic JOIN sys.columns col ON col.object_id = ic.object_id AND col.column_id = ic.column_id " \
        "WHERE ic.object_id = #{oid} AND ic.index_id = #{index_id} AND ic.is_included_column = #{included ? 1 : 0} " \
        "ORDER BY ic.key_ordinal, ic.index_column_id FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 1, '')"
    end

    def describe(name)
      obj = rows("SELECT o.object_id AS id, o.type AS type, CAST(ep.value AS nvarchar(4000)) AS cmt FROM sys.objects o " \
                 "JOIN sys.schemas sc ON sc.schema_id = o.schema_id LEFT JOIN sys.extended_properties ep ON ep.class = 1 AND ep.major_id = o.object_id " \
                 "AND ep.minor_id = 0 AND ep.name = 'MS_Description' WHERE sc.name = #{s(schema)} AND o.name = #{s(name)} AND o.type IN ('U', 'V')").first
      return nil unless obj
      raise Error, t(:error_db_mig_view, name: name) unless obj['type'].strip == 'U'
      oid = obj['id'].to_i
      m = { columns: {}, order: [], pk: nil, cons: {}, fks: {}, indexes: {}, comment: obj['cmt'], parents: [], uniques: [], oid: oid }
      rows(<<~SQL).each do |r|
        SELECT col.name, ty.name AS tname, col.max_length AS len, col.precision AS prec, col.scale, col.is_nullable AS nullable, col.is_identity AS ident,
               col.is_computed AS comp, cc.definition AS cdef, cc.is_persisted AS persisted, dc.name AS dname, dc.definition AS ddef,
               CAST(ic.seed_value AS nvarchar(40)) AS seed, CAST(ic.increment_value AS nvarchar(40)) AS inc, CAST(ep.value AS nvarchar(4000)) AS cmt
        FROM sys.columns col JOIN sys.types ty ON ty.user_type_id = col.user_type_id
        LEFT JOIN sys.computed_columns cc ON cc.object_id = col.object_id AND cc.column_id = col.column_id
        LEFT JOIN sys.default_constraints dc ON dc.parent_object_id = col.object_id AND dc.parent_column_id = col.column_id
        LEFT JOIN sys.identity_columns ic ON ic.object_id = col.object_id AND ic.column_id = col.column_id
        LEFT JOIN sys.extended_properties ep ON ep.class = 1 AND ep.major_id = col.object_id AND ep.minor_id = col.column_id AND ep.name = 'MS_Description'
        WHERE col.object_id = #{oid} ORDER BY col.column_id
      SQL
        m[:order] << r['name']
        m[:columns][r['name']] = { name: r['name'], tname: r['tname'], type: type_of(r), notnull: !r['nullable'], ident: r['ident'] ? "IDENTITY(#{r['seed']},#{r['inc']})" : nil,
                                   comp: r['comp'] ? "AS #{r['cdef']}#{' PERSISTED' if r['persisted']}" : nil, dname: r['dname'], default: r['ddef'], comment: r['cmt'] }
      end
      rows(<<~SQL).each do |r|
        SELECT i.name, i.index_id, i.type_desc, i.is_unique AS uniq, i.is_primary_key AS pk, i.is_unique_constraint AS uc, i.filter_definition AS filter,
               #{keylist(oid, 'i.index_id', false)} AS keys, #{keylist(oid, 'i.index_id', true)} AS incl
        FROM sys.indexes i WHERE i.object_id = #{oid} AND i.index_id > 0 AND i.is_hypothetical = 0 AND i.type IN (1, 2)
      SQL
        kind = r['type_desc'] == 'CLUSTERED' ? 'CLUSTERED' : 'NONCLUSTERED'
        keys = r['keys']
        if r['pk']
          m[:pk] = { name: r['name'], def: "CONSTRAINT #{q(r['name'])} PRIMARY KEY #{kind} (#{keys})", cols: cols_of(keys) }
        elsif r['uc']
          m[:cons][r['name']] = "CONSTRAINT #{q(r['name'])} UNIQUE #{kind} (#{keys})"
          m[:uniques] << cols_of(keys)
        else
          m[:indexes][r['name']] = "CREATE #{'UNIQUE ' if r['uniq']}#{kind} INDEX #{q(r['name'])} ON #{qt(name)} (#{keys})" \
                                   "#{" INCLUDE (#{r['incl']})" if r['incl'].present?}#{" WHERE #{r['filter']}" if r['filter'].present?}"
          m[:uniques] << cols_of(keys) if r['uniq'] && r['filter'].blank?
        end
      end
      rows(<<~SQL).each do |r|
        SELECT fk.name, ro.name AS rtable, rs.name AS rschema, fk.delete_referential_action_desc AS del, fk.update_referential_action_desc AS upd,
          STUFF((SELECT ',' + QUOTENAME(col.name) FROM sys.foreign_key_columns fc JOIN sys.columns col ON col.object_id = fc.parent_object_id AND col.column_id = fc.parent_column_id
                 WHERE fc.constraint_object_id = fk.object_id ORDER BY fc.constraint_column_id FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 1, '') AS cols,
          STUFF((SELECT ',' + QUOTENAME(col.name) FROM sys.foreign_key_columns fc JOIN sys.columns col ON col.object_id = fc.referenced_object_id AND col.column_id = fc.referenced_column_id
                 WHERE fc.constraint_object_id = fk.object_id ORDER BY fc.constraint_column_id FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 1, '') AS rcols
        FROM sys.foreign_keys fk JOIN sys.objects ro ON ro.object_id = fk.referenced_object_id JOIN sys.schemas rs ON rs.schema_id = ro.schema_id
        WHERE fk.parent_object_id = #{oid}
      SQL
        rt = r['rschema'] == schema ? q(r['rtable']) : "#{q(r['rschema'])}.#{q(r['rtable'])}"
        m[:fks][r['name']] = { rtable: r['rtable'], same: r['rschema'] == schema,
                               def: "CONSTRAINT #{q(r['name'])} FOREIGN KEY (#{r['cols']}) REFERENCES %s (#{r['rcols']}) ON DELETE #{r['del'].tr('_', ' ')} ON UPDATE #{r['upd'].tr('_', ' ')}", rt: rt }
        m[:parents] << r['rtable'] if r['rschema'] == schema
      end
      rows("SELECT name, definition FROM sys.check_constraints WHERE parent_object_id = #{oid}").each { |r| m[:cons][r['name']] = "CONSTRAINT #{q(r['name'])} CHECK #{r['definition']}" }
      m
    end

    def cols_of(keys)
      keys.to_s.split(',').map { |k| k.sub(/ DESC\z/, '').delete_prefix('[').delete_suffix(']').gsub(']]', ']') }
    end

    def type_of(r)
      tn = r['tname']
      len = r['len'].to_i
      case tn
      when 'varchar', 'char', 'varbinary', 'binary' then "#{tn}(#{len == -1 ? 'max' : len})"
      when 'nvarchar', 'nchar' then "#{tn}(#{len == -1 ? 'max' : len / 2})"
      when 'decimal', 'numeric' then "#{tn}(#{r['prec']},#{r['scale']})"
      when 'datetime2', 'time', 'datetimeoffset' then "#{tn}(#{r['scale']})"
      when 'float' then r['prec'].to_i == 53 ? 'float' : "float(#{r['prec']})"
      else tn
      end
    end

    def coldef(col, default: true)
      return "#{q(col[:name])} #{col[:comp]}" if col[:comp]
      d = +"#{q(col[:name])} #{col[:type]}"
      d << " #{col[:ident]}" if col[:ident]
      d << " DEFAULT #{col[:default]}" if default && col[:default]
      d << (col[:notnull] ? ' NOT NULL' : ' NULL')
      d
    end

    def fkdef(fk)
      fk[:def].sub('%s') { fk[:same] ? q(fk[:rtable]) : fk[:rt] }
    end

    def comment_sql(name, col, text, exists)
      proc_name = text.nil? ? 'sp_dropextendedproperty' : (exists ? 'sp_updateextendedproperty' : 'sp_addextendedproperty')
      args = "@name = N'MS_Description', #{"@value = #{s(text)}, " unless text.nil?}@level0type = N'SCHEMA', @level0name = #{s(schema)}, " \
             "@level1type = N'TABLE', @level1name = #{s(name)}#{", @level2type = N'COLUMN', @level2name = #{s(col)}" if col}"
      "EXEC #{proc_name} #{args}"
    end

    def plan(name, a, b)
      unique = a[:pk].present? || a[:uniques].any?
      if b.nil?
        body = a[:order].map { |n| coldef(a[:columns][n]) }
        body << a[:pk][:def] if a[:pk]
        body += a[:cons].values
        st = ["CREATE TABLE #{qt(name)} (\n  #{body.join(",\n  ")}\n)"]
        st += a[:fks].values.map { |fk| "ALTER TABLE #{qt(name)} ADD #{fkdef(fk)}" }
        st += a[:indexes].values
        st << comment_sql(name, nil, a[:comment], false) if a[:comment]
        a[:order].each { |n| st << comment_sql(name, n, a[:columns][n][:comment], false) if a[:columns][n][:comment] }
        return { status: 'new', statements: st, warnings: [], unique: unique }
      end
      st = []
      warnings = []
      a[:order].each do |n|
        x = a[:columns][n]
        y = b[:columns][n]
        if y.nil?
          st << "ALTER TABLE #{qt(name)} ADD #{coldef(x)}"
          st << comment_sql(name, n, x[:comment], false) if x[:comment]
          next
        end
        if x[:comp] != y[:comp] || x[:ident].nil? != y[:ident].nil?
          warnings << t(:text_db_mig_col_kind, name: n)
          next
        end
        next if x[:comp]
        st << "ALTER TABLE #{qt(name)} ALTER COLUMN #{coldef(x, default: false).sub(/ IDENTITY\([^)]*\)/, '')}" if x[:type] != y[:type] || x[:notnull] != y[:notnull]
        if x[:default] != y[:default]
          st << "ALTER TABLE #{qt(name)} DROP CONSTRAINT #{q(y[:dname])}" if y[:dname]
          st << "ALTER TABLE #{qt(name)} ADD DEFAULT #{x[:default]} FOR #{q(n)}" if x[:default]
        end
        st << comment_sql(name, n, x[:comment], !y[:comment].nil?) if x[:comment] != y[:comment]
      end
      (b[:order] - a[:order]).each { |n| warnings << t(:text_db_mig_keep_col, name: n) }
      if a[:pk]&.dig(:def) != b[:pk]&.dig(:def)
        if b[:pk].nil?
          st << "ALTER TABLE #{qt(name)} ADD #{a[:pk][:def]}"
        else
          warnings << t(:text_db_mig_pk_diff)
        end
      end
      a[:cons].each do |n, d|
        next if b[:cons][n] == d
        st << "ALTER TABLE #{qt(name)} DROP CONSTRAINT #{q(n)}" if b[:cons][n]
        st << "ALTER TABLE #{qt(name)} ADD #{d}"
      end
      a[:fks].each do |n, fk|
        next if b[:fks][n] && fkdef(b[:fks][n]) == fkdef(fk)
        st << "ALTER TABLE #{qt(name)} DROP CONSTRAINT #{q(n)}" if b[:fks][n]
        st << "ALTER TABLE #{qt(name)} ADD #{fkdef(fk)}"
      end
      a[:indexes].each do |n, d|
        next if b[:indexes][n] == d
        st << "DROP INDEX #{q(n)} ON #{qt(name)}" if b[:indexes][n]
        st << d
      end
      (b[:indexes].keys - a[:indexes].keys).each { |n| warnings << t(:text_db_mig_keep_index, name: n) }
      st << comment_sql(name, nil, a[:comment], !b[:comment].nil?) if a[:comment] != b[:comment]
      unique ||= b[:pk].present? || b[:uniques].any?
      { status: st.any? ? 'changed' : 'same', statements: st, warnings: warnings, unique: unique }
    end

    def data_cols(m)
      m[:order].reject { |n| m[:columns][n][:comp] || %w(timestamp rowversion).include?(m[:columns][n][:tname]) }
    end

    BINARY = %w(binary varbinary image geography geometry hierarchyid).freeze

    # 원본 칼럼을 문자열로 읽는 식
    def sel(col)
      x = q(col[:name])
      case col[:tname]
      when *BINARY then "CONVERT(varchar(max), CONVERT(varbinary(max), #{x}), 1)"
      when 'datetime', 'datetime2', 'smalldatetime', 'date', 'time', 'datetimeoffset' then "CONVERT(nvarchar(40), #{x}, 126)"
      when 'float', 'real' then "CONVERT(nvarchar(40), #{x}, 3)"
      when 'money', 'smallmoney' then "CONVERT(nvarchar(40), #{x}, 2)"
      else "CONVERT(nvarchar(max), #{x})"
      end
    end

    def lit(v, binary)
      return 'NULL' if v.nil?
      binary ? v : s(v)
    end

    # 이 테이블의 외래키·체크 + 이 테이블을 참조하는 외래키
    def fk_switch(name, oid, on)
      exec("ALTER TABLE #{qt(name)} #{on ? 'WITH NOCHECK CHECK' : 'NOCHECK'} CONSTRAINT ALL")
      rows("SELECT fk.name, sc.name AS sname, o.name AS tname FROM sys.foreign_keys fk JOIN sys.objects o ON o.object_id = fk.parent_object_id " \
           "JOIN sys.schemas sc ON sc.schema_id = o.schema_id WHERE fk.referenced_object_id = #{oid} AND fk.parent_object_id <> #{oid}").each do |r|
        exec("ALTER TABLE #{q(r['sname'])}.#{q(r['tname'])} #{on ? 'WITH NOCHECK CHECK' : 'NOCHECK'} CONSTRAINT #{q(r['name'])}")
      end
    end

    def copy_from(src, name, mode, sm, tm)
      cols = data_cols(sm) & data_cols(tm)
      raise Error, t(:error_db_mig_no_cols) if cols.empty?
      list = cols.map { |x| q(x) }.join(', ')
      bin = cols.map { |x| BINARY.include?(sm[:columns][x][:tname]) }
      ident = cols.any? { |x| tm[:columns][x][:ident] }
      key = tm[:pk] ? tm[:pk][:cols] : tm[:uniques].first
      key = nil unless key && (key - cols).empty?
      rest = cols - (key || [])
      n = 0
      buf = []
      exec('BEGIN TRANSACTION')
      fk_switch(name, tm[:oid], false)
      exec("SET IDENTITY_INSERT #{qt(name)} ON") if ident
      exec("DELETE FROM #{qt(name)}") if mode == 'replace'
      flush = lambda do
        return if buf.empty?
        values = buf.join(",\n")
        if mode == 'replace' || (mode == 'insert_new' && key.nil?)
          exec("INSERT INTO #{qt(name)} (#{list}) VALUES #{values}")
        else
          on = key.map { |x| "T.#{q(x)} = S.#{q(x)}" }.join(' AND ')
          upd = mode == 'upsert' && rest.any? ? " WHEN MATCHED THEN UPDATE SET #{rest.map { |x| "T.#{q(x)} = S.#{q(x)}" }.join(', ')}" : ''
          exec("MERGE INTO #{qt(name)} AS T USING (VALUES #{values}) AS S (#{list}) ON (#{on})#{upd} " \
               "WHEN NOT MATCHED THEN INSERT (#{list}) VALUES (#{cols.map { |x| "S.#{q(x)}" }.join(', ')});")
        end
        n += buf.size
        buf.clear
        yield n
      end
      res = src.c.execute("SELECT #{cols.map { |x| sel(sm[:columns][x]) }.join(', ')} FROM #{src.qt(name)}")
      begin
        drain(->(&blk) { res.each(as: :array, cache_rows: false, &blk) }) do |row|
          buf << "(#{row.each_with_index.map { |v, i| lit(v, bin[i]) }.join(', ')})"
          flush.call if buf.size >= ROWS
        end
      ensure
        res.cancel
      end
      flush.call
      exec("SET IDENTITY_INSERT #{qt(name)} OFF") if ident
      fk_switch(name, tm[:oid], true)
      exec('COMMIT TRANSACTION')
      n
    rescue StandardError
      begin
        exec('IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION')
      rescue StandardError
        nil
      end
      raise
    end

    def backup(name, m, gz)
      gz.write("-- #{name} 이관 전 백업 (#{Time.current.in_time_zone('Asia/Seoul').strftime('%F %T')}) — sqlcmd 로 실행\n")
      gz.write("SET XACT_ABORT ON;\nSET QUOTED_IDENTIFIER ON;\nGO\n")
      # 복원하는 때 이 테이블을 참조하는 외래키를 #mig_fk 에 저장하고 지움(그래야 DROP 가능) → 끝에 다시 만듦 (WITH NOCHECK)
      gz.write("IF OBJECT_ID('tempdb..#mig_fk') IS NOT NULL DROP TABLE #mig_fk;\n#{incoming_sql("OBJECT_ID(#{s(qt(name))}, 'U')")}\n" \
               "DECLARE @s nvarchar(max) = N''; SELECT @s = @s + N'ALTER TABLE ' + tbl + N' DROP CONSTRAINT ' + QUOTENAME(name) + N'; ' FROM #mig_fk; EXEC (@s);\nGO\n")
      gz.write("IF OBJECT_ID(#{s("#{qt(name)}")}, 'U') IS NOT NULL DROP TABLE #{qt(name)};\nGO\n")
      stmts = plan(name, m, nil)[:statements]
      gz.write("#{stmts.first};\nGO\n")
      cols = data_cols(m)
      list = cols.map { |x| q(x) }.join(', ')
      bin = cols.map { |x| BINARY.include?(m[:columns][x][:tname]) }
      ident = cols.any? { |x| m[:columns][x][:ident] }
      gz.write("SET IDENTITY_INSERT #{qt(name)} ON;\n") if ident
      n = 0
      buf = []
      res = c.execute("SELECT #{cols.map { |x| sel(m[:columns][x]) }.join(', ')} FROM #{qt(name)}")
      res.each(as: :array, cache_rows: false) do |row|
        buf << "(#{row.each_with_index.map { |v, i| lit(v, bin[i]) }.join(', ')})"
        n += 1
        next if buf.size < ROWS
        gz.write("INSERT INTO #{qt(name)} (#{list}) VALUES\n#{buf.join(",\n")};\n")
        buf.clear
      end
      res.cancel
      gz.write("INSERT INTO #{qt(name)} (#{list}) VALUES\n#{buf.join(",\n")};\n") if buf.any?
      gz.write("SET IDENTITY_INSERT #{qt(name)} OFF;\nGO\n") if ident
      stmts.drop(1).each { |x| gz.write("#{x};\nGO\n") }
      gz.write("DECLARE @s nvarchar(max) = N''; SELECT @s = @s + N'ALTER TABLE ' + tbl + N' WITH NOCHECK ADD ' + def + N'; ' FROM #mig_fk; EXEC (@s);\nGO\n")
      n
    end

    # 이 테이블(obj: OBJECT_ID 식)을 참조하는 다른 테이블의 외래키를 #mig_fk (tbl, name, def) 로
    def incoming_sql(obj)
      dd = ' COLLATE DATABASE_DEFAULT'
      cols = lambda do |side|
        "STUFF((SELECT ',' + QUOTENAME(col.name) FROM sys.foreign_key_columns fc JOIN sys.columns col ON col.object_id = fc.#{side}_object_id " \
          "AND col.column_id = fc.#{side}_column_id WHERE fc.constraint_object_id = fk.object_id " \
          "ORDER BY fc.constraint_column_id FOR XML PATH(''), TYPE).value('.', 'nvarchar(max)'), 1, 1, '')#{dd}"
      end
      "SELECT QUOTENAME(sc.name)#{dd} + '.' + QUOTENAME(o.name)#{dd} AS tbl, fk.name#{dd} AS name, 'CONSTRAINT ' + QUOTENAME(fk.name)#{dd} + ' FOREIGN KEY (' + #{cols.call('parent')} + ') REFERENCES ' + " \
        "QUOTENAME(rsc.name)#{dd} + '.' + QUOTENAME(ro.name)#{dd} + ' (' + #{cols.call('referenced')} + ') ON DELETE ' + REPLACE(fk.delete_referential_action_desc, '_', ' ')#{dd} + " \
        "' ON UPDATE ' + REPLACE(fk.update_referential_action_desc, '_', ' ')#{dd} AS def INTO #mig_fk " \
        "FROM sys.foreign_keys fk JOIN sys.objects o ON o.object_id = fk.parent_object_id JOIN sys.schemas sc ON sc.schema_id = o.schema_id " \
        "JOIN sys.objects ro ON ro.object_id = fk.referenced_object_id JOIN sys.schemas rsc ON rsc.schema_id = ro.schema_id " \
        "WHERE fk.referenced_object_id = #{obj} AND fk.parent_object_id <> fk.referenced_object_id;"
    end
  end
end
