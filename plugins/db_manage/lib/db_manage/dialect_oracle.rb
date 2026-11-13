# Oracle — ruby-oci8 (Oracle Instant Client). DB 이름 칸은 서비스 이름(예: ORCLPDB1), 기본 스키마는 접속 계정
# - 메타데이터는 ALL_* 딕셔너리 (권한이 있는 객체만 보임)
# - 다른 스키마의 함수·프로시저·패키지 소스(ALL_SOURCE)는 EXECUTE 권한 또는 SELECT_CATALOG_ROLE 이 있어야 보임
# - DB 잡은 스케줄러 작업(ALL_SCHEDULER_JOBS)
# - SQL 조회: SET TRANSACTION READ ONLY + 받는 시간 제한(recv_timeout), 건수 제한(limit+1 건까지만 fetch), 끝나면 ROLLBACK
module DbManage
  class DialectOracle < DialectBase
    def open(host, port)
      # 한글이 ? 로 바뀌지 않게 클라이언트 문자셋을 UTF-8 로 (oci8 을 처음 불러오기 전에 정해야 함, Dockerfile 에도 있음)
      ENV['NLS_LANG'] ||= 'AMERICAN_AMERICA.AL32UTF8'
      require 'oci8'
      c = OCI8.new(@server.username, @server.password, "//#{host}:#{port}/#{@server.database_name}")
      c.autocommit = false
      c.long_read_len = 1_000_000
      c.recv_timeout = [@server.timeout * 3, 60].min if c.respond_to?(:recv_timeout=)
      c
    end

    def open_write(host, port)
      ENV['NLS_LANG'] ||= 'AMERICAN_AMERICA.AL32UTF8'
      require 'oci8'
      user, pass = write_user
      c = OCI8.new(user, pass, "//#{host}:#{port}/#{@server.database_name}")
      c.autocommit = false
      c.long_read_len = 1_000_000
      c.recv_timeout = 900 if c.respond_to?(:recv_timeout=)
      c
    end

    def close(conn)
      conn&.rollback
      conn&.logoff
    rescue StandardError
      nil
    end

    def version(c)
      ver = c.oracle_server_version.to_s
      banner = safe(nil) { rows(c, 'SELECT banner_full AS b FROM v$version').first&.fetch('b', nil) } ||
               safe(nil) { rows(c, 'SELECT banner AS b FROM v$version').first&.fetch('b', nil) }
      banner.to_s.lines.first.to_s.strip.presence || "Oracle #{ver}"
    end

    def flavor(_c)
      'oracle'
    end

    def tables(c)
      rows(c, TABLES, @schema).map do |r|
        type = r['ttype'].to_s
        view = type != 'TABLE'
        { name: r['tname'], comment: r['tcomment'].presence, rows: view ? nil : r['trows']&.to_i, view: view,
          matview: type == 'MATERIALIZED VIEW', sequence: false }
      end
    end

    def columns(c)
      rows(c, COLUMNS, @schema).map do |r|
        { table: r['tname'], name: r['cname'], type: type_name(r), nullable: r['nullable'] == 'Y',
          default: r['cdefault'].to_s.strip.presence, comment: r['ccomment'].presence, position: r['column_id'].to_i }
      end
    end

    def keys(c)
      rows(c, KEYS, @schema).filter_map do |r|
        type = { 'P' => 'PK', 'U' => 'UK', 'R' => 'FK' }[r['ctype']]
        type && { table: r['tname'], column: r['cname'], type: type, rtable: r['rtable'], rcolumn: r['rcolumn'] }
      end
    end

    def indexes(c)
      safe do
        pk = rows(c, PK_INDEXES, @schema).map { |r| [r['tname'], r['iname']] }.to_set
        rows(c, INDEXES, @schema).group_by { |r| [r['tname'], r['iname']] }.map do |(t, n), list|
          cols = list.sort_by { |r| r['pos'].to_i }.map { |r| r['expr'].to_s.strip.presence || r['cname'] }
          { table: t, name: n, unique: list.first['uniq'] == 'UNIQUE', primary: pk.include?([t, n]), method: list.first['itype'], columns: cols }
        end
      end
    end

    def objects(c, _flavor, _seq_tables)
      sources = safe { rows(c, SOURCES, @schema) }.group_by { |r| [r['type'], r['name']] }
                                               .transform_values { |l| l.sort_by { |r| r['line'].to_i }.map { |r| r['text'] }.join }
      args = safe { rows(c, ARGUMENTS, @schema) }.group_by { |r| r['oname'] }
      objs = safe { rows(c, OBJECTS, @schema) }
      routine = lambda do |r, kind|
        list = (args[r['name']] || []).sort_by { |a| a['pos'].to_i }
        ret = list.find { |a| a['pos'].to_i.zero? && a['aname'].nil? }
        params = list.reject { |a| a.equal?(ret) }.map { |a| [a['aname'], a['io'], a['dtype']].compact.join(' ') }.join(', ')
        { key: r['name'], name: r['name'], kind: kind, args: params, returns: ret && ret['dtype'],
          definition: sources[[kind.upcase, r['name']]].presence, status: r['status'] == 'VALID' ? 'ENABLED' : 'DISABLED',
          created: tm(r['created']), altered: tm(r['altered']) }
      end
      functions = objs.select { |r| r['otype'] == 'FUNCTION' }.map { |r| routine.call(r, 'function') }
      procedures = objs.select { |r| r['otype'] == 'PROCEDURE' }.map { |r| routine.call(r, 'procedure') }
      packages = objs.select { |r| r['otype'] == 'PACKAGE' }.map do |r|
        spec = sources[['PACKAGE', r['name']]]
        body = sources[['PACKAGE BODY', r['name']]]
        { key: r['name'], name: r['name'], status: r['status'] == 'VALID' ? 'ENABLED' : 'DISABLED',
          comment: (body ? nil : '본문(BODY) 없음 또는 권한 없음'),
          definition: [spec, body].compact.join("\n\n").presence, created: tm(r['created']), altered: tm(r['altered']) }
      end
      views = safe { rows(c, VIEWS, @schema) }.map { |r| { key: r['name'], name: r['name'], definition: r['def'].to_s.strip.presence } }
      mviews = safe { rows(c, MVIEWS, @schema) }.map do |r|
        { key: r['name'], name: r['name'], definition: r['def'].to_s.strip.presence, matview: true,
          status: r['staleness'], last_run: tm(r['last_refresh']) }
      end
      triggers = safe { rows(c, TRIGGERS, @schema) }.map do |r|
        { key: r['name'], name: r['name'], table: r['tbl'], timing: "#{r['ttype']} #{r['evt']}".squish,
          status: r['status'], definition: "#{r['descr']}#{r['body']}".strip.presence }
      end
      sequences = safe { rows(c, SEQUENCES, @schema) }.map do |r|
        { key: r['name'], name: r['name'], type: 'NUMBER', start: r['last_number'].to_s, increment: r['inc'].to_s,
          min: r['min_value'].to_s, max: r['max_value'].to_s, cycle: r['cyc'] == 'Y', cache: r['cache_size'] }
      end
      synonyms = safe { rows(c, SYNONYMS, @schema) }.map do |r|
        { key: r['name'], name: r['name'], target: [r['towner'], r['tname']].compact.join('.') + (r['dblink'] ? "@#{r['dblink']}" : '') }
      end
      jobs = safe { rows(c, JOBS, @schema) }.map do |r|
        { key: r['name'], name: r['name'], schedule: r['repeat'].presence || tm(r['next_run']), status: r['enabled'] == 'TRUE' ? 'ENABLED' : 'DISABLED',
          last_run: tm(r['last_run']), comment: r['comments'].presence, definition: r['action'].presence }
      end
      { 'view' => views, 'matview' => mviews, 'function' => functions, 'procedure' => procedures, 'package' => packages,
        'trigger' => triggers, 'sequence' => sequences, 'synonym' => synonyms, 'event' => jobs }
    end

    # SQL 조회: 읽기 전용 트랜잭션, limit+1 건까지만 fetch
    def select(c, sql, limit, _seconds)
      c.exec('SET TRANSACTION READ ONLY')
      cursor = c.parse(sql)
      cursor.prefetch_rows = [limit + 1, 1000].min
      cursor.exec
      cols = cursor.get_col_names
      out = []
      while out.size <= limit && (row = cursor.fetch)
        out << row.map { |v| cell(v.respond_to?(:read) ? v.read : v) }  # CLOB·BLOB 은 읽어서
      end
      cursor.close
      { columns: cols, rows: out.first(limit), truncated: out.size > limit }
    ensure
      begin
        c.rollback
      rescue StandardError
        nil
      end
    end

    private

    def rows(c, sql, *binds)
      cursor = c.parse(sql)
      binds.each_with_index { |b, i| cursor.bind_param(i + 1, b) }
      cursor.exec
      names = cursor.get_col_names.map(&:downcase)
      list = []
      while (r = cursor.fetch)
        list << names.zip(r.map { |v| v.respond_to?(:read) ? v.read : (v.is_a?(String) ? text(v) : v) }).to_h
      end
      cursor.close
      list
    end

    # VARCHAR2(20) · NUMBER(10,2) · NUMBER · DATE · TIMESTAMP(6) · CHAR(1 CHAR) …
    def type_name(r)
      t = r['dtype'].to_s
      case t
      when 'VARCHAR2', 'NVARCHAR2', 'CHAR', 'NCHAR'
        "#{t}(#{r['char_length'].to_i}#{' CHAR' if r['char_used'] == 'C' && t.start_with?('VARCHAR2', 'CHAR')})"
      when 'NUMBER'
        p = r['dprec']
        s = r['dscale']
        p ? "NUMBER(#{p.to_i}#{",#{s.to_i}" if s && s.to_i != 0})" : (s && s.to_i.zero? ? 'INTEGER' : 'NUMBER')
      when 'RAW' then "RAW(#{r['dlen'].to_i})"
      when 'FLOAT' then "FLOAT(#{r['dprec'].to_i})"
      else t
      end
    end

    TABLES = <<~SQL.freeze
      SELECT o.object_name AS tname, o.object_type AS ttype, c.comments AS tcomment, t.num_rows AS trows
      FROM all_objects o
      LEFT JOIN all_tab_comments c ON c.owner = o.owner AND c.table_name = o.object_name
      LEFT JOIN all_tables t ON t.owner = o.owner AND t.table_name = o.object_name
      WHERE o.owner = :1 AND o.object_type IN ('TABLE', 'VIEW', 'MATERIALIZED VIEW') AND o.object_name NOT LIKE 'BIN$%'
        AND o.generated = 'N'
        AND NOT (o.object_type = 'TABLE' AND EXISTS (SELECT 1 FROM all_mviews m WHERE m.owner = o.owner AND m.mview_name = o.object_name))
      ORDER BY o.object_name
    SQL
    COLUMNS = <<~SQL.freeze
      SELECT c.table_name AS tname, c.column_name AS cname, c.data_type AS dtype, c.data_length AS dlen, c.data_precision AS dprec,
             c.data_scale AS dscale, c.char_length, c.char_used, c.nullable, c.data_default AS cdefault, c.column_id,
             cc.comments AS ccomment
      FROM all_tab_columns c
      LEFT JOIN all_col_comments cc ON cc.owner = c.owner AND cc.table_name = c.table_name AND cc.column_name = c.column_name
      WHERE c.owner = :1 AND c.table_name NOT LIKE 'BIN$%'
      ORDER BY c.table_name, c.column_id
    SQL
    KEYS = <<~SQL.freeze
      SELECT cc.table_name AS tname, cc.column_name AS cname, c.constraint_type AS ctype, rc.table_name AS rtable, rcc.column_name AS rcolumn
      FROM all_constraints c
      JOIN all_cons_columns cc ON cc.owner = c.owner AND cc.constraint_name = c.constraint_name
      LEFT JOIN all_constraints rc ON rc.owner = c.r_owner AND rc.constraint_name = c.r_constraint_name
      LEFT JOIN all_cons_columns rcc ON rcc.owner = rc.owner AND rcc.constraint_name = rc.constraint_name AND rcc.position = cc.position
      WHERE c.owner = :1 AND c.constraint_type IN ('P', 'U', 'R')
    SQL
    PK_INDEXES = <<~SQL.freeze
      SELECT table_name AS tname, index_name AS iname FROM all_constraints WHERE owner = :1 AND constraint_type = 'P' AND index_name IS NOT NULL
    SQL
    INDEXES = <<~SQL.freeze
      SELECT i.table_name AS tname, i.index_name AS iname, i.uniqueness AS uniq, i.index_type AS itype,
             ic.column_name AS cname, ic.column_position AS pos, ie.column_expression AS expr
      FROM all_indexes i
      JOIN all_ind_columns ic ON ic.index_owner = i.owner AND ic.index_name = i.index_name
      LEFT JOIN all_ind_expressions ie ON ie.index_owner = ic.index_owner AND ie.index_name = ic.index_name AND ie.column_position = ic.column_position
      WHERE i.table_owner = :1 AND i.index_type <> 'LOB'
      ORDER BY i.table_name, i.index_name, ic.column_position
    SQL
    OBJECTS = <<~SQL.freeze
      SELECT object_name AS name, object_type AS otype, status, created, last_ddl_time AS altered
      FROM all_objects WHERE owner = :1 AND object_type IN ('FUNCTION', 'PROCEDURE', 'PACKAGE') ORDER BY object_name
    SQL
    SOURCES = <<~SQL.freeze
      SELECT name, type, line, text FROM all_source
      WHERE owner = :1 AND type IN ('FUNCTION', 'PROCEDURE', 'PACKAGE', 'PACKAGE BODY') ORDER BY name, type, line
    SQL
    ARGUMENTS = <<~SQL.freeze
      SELECT object_name AS oname, argument_name AS aname, position AS pos, in_out AS io, data_type AS dtype
      FROM all_arguments WHERE owner = :1 AND package_name IS NULL AND data_level = 0
    SQL
    VIEWS = <<~SQL.freeze
      SELECT view_name AS name, text AS def FROM all_views WHERE owner = :1 ORDER BY view_name
    SQL
    MVIEWS = <<~SQL.freeze
      SELECT mview_name AS name, query AS def, staleness, last_refresh_date AS last_refresh FROM all_mviews WHERE owner = :1 ORDER BY mview_name
    SQL
    TRIGGERS = <<~SQL.freeze
      SELECT trigger_name AS name, table_name AS tbl, trigger_type AS ttype, triggering_event AS evt, status,
             description AS descr, trigger_body AS body
      FROM all_triggers WHERE owner = :1 ORDER BY trigger_name
    SQL
    SEQUENCES = <<~SQL.freeze
      SELECT sequence_name AS name, min_value, max_value, increment_by AS inc, cycle_flag AS cyc, cache_size, last_number
      FROM all_sequences WHERE sequence_owner = :1 ORDER BY sequence_name
    SQL
    SYNONYMS = <<~SQL.freeze
      SELECT synonym_name AS name, table_owner AS towner, table_name AS tname, db_link AS dblink
      FROM all_synonyms WHERE owner = :1 ORDER BY synonym_name
    SQL
    JOBS = <<~SQL.freeze
      SELECT job_name AS name, job_action AS action, repeat_interval AS repeat, enabled, last_start_date AS last_run,
             next_run_date AS next_run, comments
      FROM all_scheduler_jobs WHERE owner = :1 ORDER BY job_name
    SQL
  end
end
