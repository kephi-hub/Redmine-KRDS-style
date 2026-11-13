# PostgreSQL — pg, default_transaction_read_only=on. 조회 전용 계정으로 함수·트리거·시퀀스 모두 보임, DB 잡은 pg_cron 있을 때만
module DbManage
  class DialectPostgresql < DialectBase
    def open(host, port)
      require 'pg'
      t = @server.timeout
      PG.connect(host: host, port: port, dbname: @server.database_name, user: @server.username,
                 password: @server.password, connect_timeout: t, sslmode: 'prefer', application_name: 'redmine_db_manage',
                 options: "-c statement_timeout=#{t * 3000} -c default_transaction_read_only=on")
    end

    # 이관용 쓰기 연결 — 읽기 전용·시간 제한 없음
    def open_write(host, port)
      require 'pg'
      user, pass = write_user
      PG.connect(host: host, port: port, dbname: @server.database_name, user: user, password: pass, connect_timeout: @server.timeout,
                 sslmode: 'prefer', application_name: 'redmine_db_migrate', options: '-c statement_timeout=0')
    end

    def version(c)
      c.exec('SHOW server_version').getvalue(0, 0)
    end

    def flavor(_c)
      'postgresql'
    end

    def tables(c)
      fetch(c, PG_TABLES).map do |r|
        rows = r['trows'].to_i
        kind = r['ttype'].to_s
        { name: r['tname'], comment: r['tcomment'].presence, rows: %w(v m).include?(kind) || rows.negative? ? nil : rows,
          view: %w(v m).include?(kind), matview: kind == 'm', sequence: false }
      end
    end

    def columns(c)
      fetch(c, PG_COLUMNS).map do |r|
        { table: r['tname'], name: r['cname'], type: r['ctype'], nullable: r['cnull'] == 'YES', default: r['cdefault'],
          comment: r['ccomment'].presence, position: r['cpos'].to_i }
      end
    end

    def keys(c)
      fetch(c, PG_KEYS).filter_map do |r|
        type = { 'p' => 'PK', 'u' => 'UK', 'f' => 'FK' }[r['ctype']]
        type && { table: r['tname'], column: r['cname'], type: type, rtable: r['rtable'], rcolumn: r['rcolumn'] }
      end
    end

    def indexes(c)
      safe do
        fetch(c, PG_INDEXES).map do |r|
          { table: r['tname'], name: r['iname'], unique: r['uniq'] == 't', primary: r['prim'] == 't', method: r['am'],
            columns: r['cols'].to_s.split("\x1f").reject(&:empty?), definition: r['def'] }
        end
      end
    end

    # SQL 조회: 읽기 전용 트랜잭션 + statement_timeout, 커서로 limit+1 건까지만 받음 (SHOW·EXPLAIN 은 그대로)
    def select(c, sql, limit, seconds)
      c.exec('BEGIN READ ONLY')
      c.exec("SET LOCAL statement_timeout = #{seconds * 1000}")
      if sql.match?(/\A\s*(select|with|values|table)\b/i)
        c.exec("DECLARE redmine_q NO SCROLL CURSOR FOR #{sql}")
        res = c.exec("FETCH #{limit + 1} FROM redmine_q")
      else
        res = c.exec(sql)
      end
      rows = res.values.first(limit + 1)
      { columns: res.fields, rows: rows.first(limit).map { |row| row.map { |v| cell(v) } }, truncated: rows.size > limit }
    ensure
      begin
        c.exec('ROLLBACK')
      rescue StandardError
        nil
      end
    end

    def objects(c, _flavor, _seq_tables)
      views = fetch(c, PG_VIEWS).map do |r|
        { key: r['tname'], name: r['tname'], definition: r['vdef'].presence, matview: r['kind'] == 'm', owner: r['owner'] }
      end
      routines = fetch(c, PG_ROUTINES).map do |r|
        { key: "#{r['name']}(#{r['args']})", name: r['name'], kind: r['kind'] == 'p' ? 'procedure' : 'function', args: r['args'],
          returns: r['kind'] == 'p' ? nil : r['returns'], comment: r['comment'].presence, definition: r['def'].presence,
          language: r['lang'], security: r['secdef'] == 't' ? 'DEFINER' : 'INVOKER',
          volatility: { 'i' => 'IMMUTABLE', 's' => 'STABLE', 'v' => 'VOLATILE' }[r['vol']], definer: r['owner'] }
      end
      triggers = fetch(c, PG_TRIGGERS).map do |r|
        t = r['tgtype'].to_i
        timing = t & 64 != 0 ? 'INSTEAD OF' : (t & 2 != 0 ? 'BEFORE' : 'AFTER')
        events = { 4 => 'INSERT', 8 => 'DELETE', 16 => 'UPDATE', 32 => 'TRUNCATE' }.select { |bit, _| t & bit != 0 }.values
        { key: r['name'], name: r['name'], table: r['tbl'], timing: "#{timing} #{events.join(' OR ')}#{t & 1 != 0 ? ' (행 단위)' : ''}",
          status: r['en'] == 'D' ? 'DISABLED' : 'ENABLED', definition: r['def'] }
      end
      sequences = fetch(c, PG_SEQUENCES).map do |r|
        { key: r['name'], name: r['name'], comment: r['comment'].presence, type: r['dtype'], start: r['start'], increment: r['inc'],
          min: r['min'], max: r['max'], cycle: r['cyc'] == 't', cache: r['cache'], owned_by: r['owned'] }
      end
      # DB 잡: pg_cron 확장이 있을 때만 (작업은 만든 계정만 볼 수 있음)
      events = nil
      if c.exec("SELECT to_regclass('cron.job') IS NOT NULL").getvalue(0, 0) == 't'
        events = safe do
          c.exec(PG_CRON).to_a.map do |r|
            { key: r['jobid'].to_s, name: r['jobname'].presence || "job #{r['jobid']}", schedule: r['schedule'],
              status: r['active'] == 't' ? 'ENABLED' : 'DISABLED', definition: r['command'], definer: r['username'] }
          end
        end
      end
      types = safe { DbManage::MigratePostgresql.new(c, @schema).type_defs.map { |n, d| { key: n, name: n, definition: d } } }
      { 'view' => views.reject { |v| v[:matview] }, 'matview' => views.select { |v| v[:matview] }, 'type' => types,
        'function' => routines.select { |r| r[:kind] == 'function' }, 'procedure' => routines.select { |r| r[:kind] == 'procedure' },
        'trigger' => triggers, 'sequence' => sequences, 'event' => events }
    end

    private

    def fetch(conn, sql)
      conn.exec_params(sql, [@schema]).to_a
    end

    PG_VIEWS = <<~SQL.freeze
      SELECT c.relname AS tname, c.relkind AS kind, pg_get_viewdef(c.oid, true) AS vdef, pg_get_userbyid(c.relowner) AS owner
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = $1 AND c.relkind IN ('v', 'm') ORDER BY c.relname
    SQL
    PG_ROUTINES = <<~SQL.freeze
      SELECT p.proname AS name, p.prokind AS kind, pg_get_function_identity_arguments(p.oid) AS args,
             pg_get_function_result(p.oid) AS returns, obj_description(p.oid, 'pg_proc') AS comment, l.lanname AS lang,
             p.prosecdef AS secdef, p.provolatile AS vol, pg_get_userbyid(p.proowner) AS owner,
             CASE WHEN l.lanname IN ('internal', 'c') THEN NULL ELSE pg_get_functiondef(p.oid) END AS def
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace JOIN pg_language l ON l.oid = p.prolang
      WHERE n.nspname = $1 AND p.prokind IN ('f', 'p')
        AND NOT EXISTS (SELECT 1 FROM pg_depend d WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid AND d.deptype = 'e')
      ORDER BY p.proname, 3
    SQL
    PG_TRIGGERS = <<~SQL.freeze
      SELECT t.tgname AS name, c.relname AS tbl, pg_get_triggerdef(t.oid, true) AS def, t.tgenabled AS en, t.tgtype AS tgtype
      FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = $1 AND NOT t.tgisinternal ORDER BY t.tgname
    SQL
    PG_SEQUENCES = <<~SQL.freeze
      SELECT c.relname AS name, format_type(s.seqtypid, NULL) AS dtype, s.seqstart AS start, s.seqincrement AS inc,
             s.seqmin AS min, s.seqmax AS max, s.seqcycle AS cyc, s.seqcache AS cache, obj_description(c.oid, 'pg_class') AS comment,
             (SELECT dc.relname || '.' || a.attname FROM pg_depend d JOIN pg_class dc ON dc.oid = d.refobjid
                JOIN pg_attribute a ON a.attrelid = d.refobjid AND a.attnum = d.refobjsubid
              WHERE d.objid = c.oid AND d.deptype IN ('a', 'i') LIMIT 1) AS owned
      FROM pg_sequence s JOIN pg_class c ON c.oid = s.seqrelid JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = $1 ORDER BY c.relname
    SQL
    PG_CRON = <<~SQL.freeze
      SELECT jobid, jobname, schedule, command, active, username FROM cron.job WHERE database = current_database() ORDER BY jobid
    SQL
    PG_TABLES = <<~SQL.freeze
      SELECT c.relname AS tname, obj_description(c.oid, 'pg_class') AS tcomment, c.reltuples::bigint AS trows, c.relkind AS ttype
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = $1 AND c.relkind IN ('r', 'p', 'v', 'm') AND NOT c.relispartition
      ORDER BY c.relname
    SQL
    PG_COLUMNS = <<~SQL.freeze
      SELECT c.relname AS tname, a.attname AS cname, format_type(a.atttypid, a.atttypmod) AS ctype,
             CASE WHEN a.attnotnull THEN 'NO' ELSE 'YES' END AS cnull, pg_get_expr(d.adbin, d.adrelid) AS cdefault,
             col_description(c.oid, a.attnum) AS ccomment, a.attnum AS cpos
      FROM pg_attribute a
      JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace
      LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
      WHERE n.nspname = $1 AND c.relkind IN ('r', 'p', 'v', 'm') AND NOT c.relispartition AND a.attnum > 0 AND NOT a.attisdropped
      ORDER BY c.relname, a.attnum
    SQL
    PG_KEYS = <<~SQL.freeze
      SELECT c.relname AS tname, a.attname AS cname, con.contype::text AS ctype, rc.relname AS rtable, ra.attname AS rcolumn
      FROM pg_constraint con
      JOIN pg_class c ON c.oid = con.conrelid JOIN pg_namespace n ON n.oid = c.relnamespace
      CROSS JOIN LATERAL unnest(con.conkey) WITH ORDINALITY AS k(attnum, ord)
      JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = k.attnum
      LEFT JOIN pg_class rc ON rc.oid = con.confrelid
      LEFT JOIN pg_attribute ra ON ra.attrelid = con.confrelid AND ra.attnum = con.confkey[k.ord]
      WHERE n.nspname = $1 AND con.contype IN ('p', 'u', 'f')
    SQL
    # 인덱스 컬럼은 구분 문자(\x1f)로 이어 받음 (식 인덱스는 식 그대로)
    PG_INDEXES = <<~SQL.freeze
      SELECT t.relname AS tname, i.relname AS iname, ix.indisunique AS uniq, ix.indisprimary AS prim, am.amname AS am,
             pg_get_indexdef(ix.indexrelid) AS def,
             (SELECT string_agg(pg_get_indexdef(ix.indexrelid, k.ord, true), chr(31) ORDER BY k.ord)
                FROM generate_series(1, ix.indnkeyatts) AS k(ord)) AS cols
      FROM pg_index ix
      JOIN pg_class i ON i.oid = ix.indexrelid JOIN pg_class t ON t.oid = ix.indrelid
      JOIN pg_namespace n ON n.oid = t.relnamespace JOIN pg_am am ON am.oid = i.relam
      WHERE n.nspname = $1 ORDER BY t.relname, i.relname
    SQL
  end
end
