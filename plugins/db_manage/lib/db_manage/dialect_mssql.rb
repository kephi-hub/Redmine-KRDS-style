# MS SQL Server — tiny_tds (FreeTDS). 기본 스키마 dbo
# - 메타데이터는 sys 카탈로그 (설명은 MS_Description 확장 속성)
# - DB 잡은 SQL Server 에이전트 작업(msdb) — msdb 의 SQLAgentReaderRole 이 있어야 보임
# - SQL 조회: SQL Server 에는 읽기 전용 트랜잭션이 없어 트랜잭션 안에서 실행하고 항상 ROLLBACK, SET ROWCOUNT 로 건수 제한
module DbManage
  class DialectMssql < DialectBase
    def open(host, port)
      require 'tiny_tds'
      t = @server.timeout
      c = TinyTds::Client.new(host: host, port: port, username: @server.username, password: @server.password,
                              database: @server.database_name, login_timeout: t, timeout: [t * 3, 60].min,
                              appname: 'redmine_db_manage', encoding: 'UTF-8')
      run(c, 'SET LOCK_TIMEOUT 5000; SET TEXTSIZE 2147483647; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON')
      c
    end

    def open_write(host, port)
      require 'tiny_tds'
      user, pass = write_user
      c = TinyTds::Client.new(host: host, port: port, username: user, password: pass, database: @server.database_name,
                              login_timeout: @server.timeout, timeout: 900, appname: 'redmine_db_migrate', encoding: 'UTF-8')
      c.execute('SET TEXTSIZE 2147483647; SET ANSI_NULLS ON; SET QUOTED_IDENTIFIER ON; SET ANSI_WARNINGS ON; SET ANSI_PADDING ON; SET CONCAT_NULL_YIELDS_NULL ON; SET ARITHABORT ON').do
      c
    end

    def close(conn)
      conn&.close
    rescue StandardError
      nil
    end

    def version(c)
      rows(c, 'SELECT @@VERSION AS v').first['v'].to_s.lines.first.to_s.strip
    end

    def flavor(_c)
      'mssql'
    end

    def tables(c)
      rows(c, sql(TABLES)).map do |r|
        view = r['ttype'].to_s.strip == 'V'
        { name: r['tname'], comment: r['tcomment'].presence, rows: view ? nil : r['trows'].to_i, view: view, matview: false, sequence: false }
      end
    end

    def columns(c)
      rows(c, sql(COLUMNS)).map do |r|
        { table: r['tname'], name: r['cname'], type: type_name(r), nullable: truthy(r['is_nullable']),
          default: r['cdefault'].to_s.sub(/\A\((.*)\)\z/m, '\1').presence, comment: r['ccomment'].presence, position: r['column_id'].to_i }
      end
    end

    def keys(c)
      rows(c, sql(KEYS)).map do |r|
        { table: r['tname'], column: r['cname'], type: r['ktype'], rtable: r['rtable'], rcolumn: r['rcolumn'] }
      end
    end

    def indexes(c)
      safe do
        rows(c, sql(INDEXES)).group_by { |r| [r['tname'], r['iname']] }.map do |(t, n), list|
          keycols = list.reject { |r| truthy(r['incl']) }.sort_by { |r| r['ord'].to_i }.map { |r| r['cname'] }
          incl = list.select { |r| truthy(r['incl']) }.map { |r| "(포함) #{r['cname']}" }
          { table: t, name: n, unique: truthy(list.first['uniq']), primary: truthy(list.first['prim']),
            method: list.first['itype'], columns: keycols + incl }
        end
      end
    end

    def objects(c, _flavor, _seq_tables)
      views = safe { rows(c, sql(VIEWS)) }.map { |r| { key: r['name'], name: r['name'], definition: r['def'].presence, comment: r['comment'].presence } }
      params = safe { rows(c, sql(PARAMS)) }.group_by { |r| r['oname'] }
      routines = safe { rows(c, sql(ROUTINES)) }.map do |r|
        ps = params[r['name']] || []
        ret = ps.find { |p| p['pid'].to_i.zero? }
        args = ps.reject { |p| p['pid'].to_i.zero? }.sort_by { |p| p['pid'].to_i }
                 .map { |p| [p['pname'], type_name(p), (truthy(p['is_output']) ? 'OUTPUT' : nil)].compact.join(' ') }.join(', ')
        proc = %w(P PC).include?(r['otype'].to_s.strip)
        kind_label = { 'FN' => 'SCALAR', 'IF' => 'INLINE TABLE', 'TF' => 'TABLE', 'FS' => 'CLR SCALAR', 'FT' => 'CLR TABLE' }[r['otype'].to_s.strip]
        { key: r['name'], name: r['name'], kind: proc ? 'procedure' : 'function', args: args,
          returns: proc ? nil : (ret ? type_name(ret) : (kind_label&.include?('TABLE') ? 'TABLE' : nil)),
          comment: r['comment'].presence, definition: r['def'].presence, language: kind_label,
          created: tm(r['created']), altered: tm(r['altered']) }
      end
      triggers = safe { rows(c, sql(TRIGGERS)) }.map do |r|
        { key: r['name'], name: r['name'], table: r['tbl'], timing: "#{truthy(r['instead']) ? 'INSTEAD OF' : 'AFTER'} #{r['events']}",
          status: truthy(r['disabled']) ? 'DISABLED' : 'ENABLED', definition: r['def'].presence, created: tm(r['created']) }
      end
      sequences = safe { rows(c, sql(SEQUENCES)) }.map do |r|
        { key: r['name'], name: r['name'], type: r['tyname'], start: r['start_value'].to_s, increment: r['increment'].to_s,
          min: r['minimum_value'].to_s, max: r['maximum_value'].to_s, cycle: truthy(r['is_cycling']), cache: r['cache_size'] }
      end
      synonyms = safe { rows(c, sql(SYNONYMS)) }.map { |r| { key: r['name'], name: r['name'], target: r['target'], comment: nil } }
      # SQL Server 에이전트 작업: 이 DB 에서 실행되는 작업만 (권한이 없으면 빈 목록 → 화면에서 안내)
      jobs = safe { rows(c, JOBS.gsub('@db', quote_str(@server.database_name))) }.group_by { |r| r['job_id'] }.map do |_, list|
        r = list.first
        { key: r['name'], name: r['name'], schedule: list.map { |x| x['sched'] }.compact.uniq.join(', ').presence,
          status: truthy(r['enabled']) ? 'ENABLED' : 'DISABLED', comment: r['description'].presence,
          definition: list.sort_by { |x| x['step_id'].to_i }.map { |x| "-- #{x['step_name']}\n#{x['command']}" }.uniq.join("\n\n").presence,
          last_run: r['last_run'] }
      end
      types = safe { DbManage::MigrateMssql.new(c, @schema).type_defs.map { |n, d| { key: n, name: n, definition: d } } }
      { 'view' => views, 'type' => types, 'function' => routines.select { |r| r[:kind] == 'function' }, 'procedure' => routines.select { |r| r[:kind] == 'procedure' },
        'trigger' => triggers, 'sequence' => sequences, 'synonym' => synonyms, 'event' => jobs }
    end

    # SQL 조회: 트랜잭션 안에서 실행하고 항상 되돌림, SET ROWCOUNT 로 limit+1 건까지
    def select(c, sql, limit, _seconds)
      run(c, "SET ROWCOUNT #{limit + 1}; BEGIN TRANSACTION")
      res = c.execute(sql)
      data = res.each(as: :array, cache_rows: true, empty_sets: true)
      fields = res.fields || []
      res.cancel
      rows = data.first(limit + 1)
      { columns: fields.map(&:to_s), rows: rows.first(limit).map { |row| row.map { |v| cell(v) } }, truncated: rows.size > limit }
    ensure
      begin
        run(c, 'IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION; SET ROWCOUNT 0')
      rescue StandardError
        nil
      end
    end

    private

    def run(c, sql)
      c.execute(sql).do
    end

    def rows(c, sql)
      res = c.execute(sql)
      list = res.each(as: :hash, cache_rows: true).map { |h| h.transform_values { |v| v.is_a?(String) ? text(v) : v } }
      res.cancel
      list
    end

    def sql(template)
      template.gsub('@schema', quote_str(@schema))
    end

    def quote_str(v)
      "N'#{v.to_s.gsub("'", "''")}'"
    end

    def truthy(v)
      v == true || v.to_s == '1'
    end

    # varchar(50) · nvarchar(max) · decimal(12,2) · datetime2(7) …
    def type_name(r)
      t = r['tyname'].to_s
      len = r['max_length'].to_i
      case t
      when 'varchar', 'char', 'varbinary', 'binary' then "#{t}(#{len == -1 ? 'max' : len})"
      when 'nvarchar', 'nchar' then "#{t}(#{len == -1 ? 'max' : len / 2})"
      when 'decimal', 'numeric' then "#{t}(#{r['precision']},#{r['scale']})"
      when 'datetime2', 'time', 'datetimeoffset' then "#{t}(#{r['scale']})"
      else t
      end
    end

    DESC = "LEFT JOIN sys.extended_properties ep ON ep.class = 1 AND ep.name = 'MS_Description'"
    TABLES = <<~SQL.freeze
      SELECT o.name AS tname, CAST(ep.value AS NVARCHAR(4000)) AS tcomment, o.type AS ttype,
             (SELECT SUM(p.rows) FROM sys.partitions p WHERE p.object_id = o.object_id AND p.index_id IN (0, 1)) AS trows
      FROM sys.objects o JOIN sys.schemas s ON s.schema_id = o.schema_id
      #{DESC} AND ep.major_id = o.object_id AND ep.minor_id = 0
      WHERE s.name = @schema AND o.type IN ('U', 'V') AND o.is_ms_shipped = 0 ORDER BY o.name
    SQL
    COLUMNS = <<~SQL.freeze
      SELECT o.name AS tname, c.name AS cname, t.name AS tyname, c.max_length, c.precision, c.scale, c.is_nullable, c.column_id,
             dc.definition AS cdefault, CAST(ep.value AS NVARCHAR(4000)) AS ccomment
      FROM sys.columns c JOIN sys.objects o ON o.object_id = c.object_id JOIN sys.schemas s ON s.schema_id = o.schema_id
      JOIN sys.types t ON t.user_type_id = c.user_type_id
      LEFT JOIN sys.default_constraints dc ON dc.object_id = c.default_object_id
      #{DESC} AND ep.major_id = c.object_id AND ep.minor_id = c.column_id
      WHERE s.name = @schema AND o.type IN ('U', 'V') AND o.is_ms_shipped = 0 ORDER BY o.name, c.column_id
    SQL
    KEYS = <<~SQL.freeze
      SELECT o.name AS tname, c.name AS cname, CASE WHEN i.is_primary_key = 1 THEN 'PK' ELSE 'UK' END AS ktype,
             CAST(NULL AS sysname) AS rtable, CAST(NULL AS sysname) AS rcolumn
      FROM sys.indexes i JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
      JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
      JOIN sys.objects o ON o.object_id = i.object_id JOIN sys.schemas s ON s.schema_id = o.schema_id
      WHERE s.name = @schema AND (i.is_primary_key = 1 OR i.is_unique_constraint = 1)
      UNION ALL
      SELECT tp.name, cp.name, 'FK', tr.name, cr.name
      FROM sys.foreign_key_columns fkc
      JOIN sys.objects tp ON tp.object_id = fkc.parent_object_id
      JOIN sys.columns cp ON cp.object_id = fkc.parent_object_id AND cp.column_id = fkc.parent_column_id
      JOIN sys.objects tr ON tr.object_id = fkc.referenced_object_id
      JOIN sys.columns cr ON cr.object_id = fkc.referenced_object_id AND cr.column_id = fkc.referenced_column_id
      JOIN sys.schemas s ON s.schema_id = tp.schema_id
      WHERE s.name = @schema
    SQL
    INDEXES = <<~SQL.freeze
      SELECT o.name AS tname, i.name AS iname, i.is_unique AS uniq, i.is_primary_key AS prim, i.type_desc AS itype,
             c.name AS cname, ic.key_ordinal AS ord, ic.is_included_column AS incl
      FROM sys.indexes i JOIN sys.index_columns ic ON ic.object_id = i.object_id AND ic.index_id = i.index_id
      JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
      JOIN sys.objects o ON o.object_id = i.object_id JOIN sys.schemas s ON s.schema_id = o.schema_id
      WHERE s.name = @schema AND o.type = 'U' AND i.name IS NOT NULL ORDER BY o.name, i.name, ic.key_ordinal
    SQL
    VIEWS = <<~SQL.freeze
      SELECT v.name, OBJECT_DEFINITION(v.object_id) AS def, CAST(ep.value AS NVARCHAR(4000)) AS comment
      FROM sys.views v JOIN sys.schemas s ON s.schema_id = v.schema_id
      #{DESC} AND ep.major_id = v.object_id AND ep.minor_id = 0
      WHERE s.name = @schema AND v.is_ms_shipped = 0 ORDER BY v.name
    SQL
    ROUTINES = <<~SQL.freeze
      SELECT o.name, o.type AS otype, OBJECT_DEFINITION(o.object_id) AS def, o.create_date AS created, o.modify_date AS altered,
             CAST(ep.value AS NVARCHAR(4000)) AS comment
      FROM sys.objects o JOIN sys.schemas s ON s.schema_id = o.schema_id
      #{DESC} AND ep.major_id = o.object_id AND ep.minor_id = 0
      WHERE s.name = @schema AND o.type IN ('FN', 'IF', 'TF', 'FS', 'FT', 'P', 'PC') AND o.is_ms_shipped = 0 ORDER BY o.name
    SQL
    PARAMS = <<~SQL.freeze
      SELECT o.name AS oname, p.parameter_id AS pid, p.name AS pname, t.name AS tyname, p.max_length, p.precision, p.scale, p.is_output
      FROM sys.parameters p JOIN sys.objects o ON o.object_id = p.object_id JOIN sys.schemas s ON s.schema_id = o.schema_id
      JOIN sys.types t ON t.user_type_id = p.user_type_id
      WHERE s.name = @schema AND o.type IN ('FN', 'IF', 'TF', 'FS', 'FT', 'P', 'PC')
    SQL
    TRIGGERS = <<~SQL.freeze
      SELECT tr.name, o.name AS tbl, tr.is_instead_of_trigger AS instead, tr.is_disabled AS disabled, tr.create_date AS created,
             OBJECT_DEFINITION(tr.object_id) AS def,
             STUFF((SELECT ' OR ' + te.type_desc FROM sys.trigger_events te WHERE te.object_id = tr.object_id FOR XML PATH('')), 1, 4, '') AS events
      FROM sys.triggers tr JOIN sys.objects o ON o.object_id = tr.parent_id JOIN sys.schemas s ON s.schema_id = o.schema_id
      WHERE s.name = @schema AND tr.is_ms_shipped = 0 ORDER BY tr.name
    SQL
    SEQUENCES = <<~SQL.freeze
      SELECT sq.name, t.name AS tyname, sq.start_value, sq.increment, sq.minimum_value, sq.maximum_value, sq.is_cycling, sq.cache_size
      FROM sys.sequences sq JOIN sys.schemas s ON s.schema_id = sq.schema_id JOIN sys.types t ON t.user_type_id = sq.user_type_id
      WHERE s.name = @schema ORDER BY sq.name
    SQL
    SYNONYMS = <<~SQL.freeze
      SELECT sy.name, sy.base_object_name AS target FROM sys.synonyms sy JOIN sys.schemas s ON s.schema_id = sy.schema_id
      WHERE s.name = @schema ORDER BY sy.name
    SQL
    JOBS = <<~SQL.freeze
      SELECT j.job_id, j.name, j.enabled, j.description, st.step_id, st.step_name, st.command, sc.name AS sched,
             CASE WHEN h.run_date IS NULL THEN NULL ELSE CONCAT(h.run_date, ' ', RIGHT('000000' + CAST(h.run_time AS varchar(6)), 6)) END AS last_run
      FROM msdb.dbo.sysjobs j
      JOIN msdb.dbo.sysjobsteps st ON st.job_id = j.job_id
      LEFT JOIN msdb.dbo.sysjobschedules js ON js.job_id = j.job_id
      LEFT JOIN msdb.dbo.sysschedules sc ON sc.schedule_id = js.schedule_id
      OUTER APPLY (SELECT TOP 1 run_date, run_time FROM msdb.dbo.sysjobhistory hh WHERE hh.job_id = j.job_id AND hh.step_id = 0 ORDER BY run_date DESC, run_time DESC) h
      WHERE j.job_id IN (SELECT job_id FROM msdb.dbo.sysjobsteps WHERE database_name = @db)
      ORDER BY j.name, st.step_id
    SQL
  end
end
