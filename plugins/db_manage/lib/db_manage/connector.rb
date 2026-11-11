# 원격 DB 에 읽기 전용으로 접속해 테이블·컬럼·키 정보(메타데이터)만 읽음 — 데이터 조회·변경 SQL 은 실행하지 않음
# - MariaDB·MySQL: mysql2 (세션을 READ ONLY 로), PostgreSQL: pg (default_transaction_read_only=on)
# - 결과 형식은 DB 종류와 관계없이 같음
#   tables:  [{ name:, comment:, rows:, view: }]
#   columns: { 테이블명 => [{ name:, type:, nullable:, default:, keys: ['PK','UK','FK'], ref:, comment:, position: }] }
#   objects (snapshot(objects: true) 일 때): { 종류 => [{ key:, name:, ... , definition: }] } — 종류는 DB 마다 다름 (KINDS)
#   종류 목록이 nil 이면 그 DB 에 없는 기능(예: pg_cron 없는 PostgreSQL 의 DB 잡)
module DbManage
  class Error < StandardError; end

  class Connector
    # DB 종류별 탭 (조사: MariaDB 10.11 · MySQL 8.4 · PostgreSQL 17)
    KINDS = {
      'mariadb' => %w(table view function procedure trigger event sequence),
      'mysql' => %w(table view function procedure trigger event),
      'postgresql' => %w(table view matview function procedure trigger sequence event)
    }.freeze
    def initialize(server, schema = nil)
      @server = server
      @schema = schema.presence || (server.adapter == 'postgresql' ? 'public' : server.database_name)
    end

    attr_reader :schema

    # 연결 시험: DB 버전 문자열
    def version
      connect do |c|
        mariadb? ? c.query('SELECT VERSION() AS v').first['v'] : c.exec('SHOW server_version').getvalue(0, 0)
      end
    end

    # 스키마 전체 (테이블 목록 + 컬럼 + 키) 한 번에. objects: true 면 뷰 정의·함수·프로시저·트리거·DB 잡·시퀀스도
    def snapshot(objects: false)
      connect do |c|
        flavor = mariadb? ? (c.query('SELECT VERSION() AS v').first['v'].to_s.include?('MariaDB') ? 'mariadb' : 'mysql') : 'postgresql'
        all = fetch(c, mariadb? ? MY_TABLES : PG_TABLES).map do |r|
          rows = r['trows'].to_i
          ttype = r['ttype'].to_s
          view = ttype.match?(/VIEW|\Av\z|\Am\z/)
          # MariaDB 는 뷰 설명에 'VIEW' 를 넣어 줌 → 빈 설명으로
          comment = r['tcomment'].presence unless view && r['tcomment'] == 'VIEW'
          { name: r['tname'], comment: comment, rows: view || rows.negative? ? nil : rows, view: view,
            matview: ttype == 'm', sequence: ttype == 'SEQUENCE' }
        end
        # MariaDB 시퀀스는 TABLES 에 함께 나옴 → 객체 쪽으로
        tables = all.reject { |t| t[:sequence] }
        keys = Hash.new { |h, k| h[k] = { keys: [], ref: nil } }
        fetch(c, mariadb? ? MY_KEYS : PG_KEYS).each do |r|
          k = keys[[r['tname'], r['cname']]]
          label = { 'PRIMARY KEY' => 'PK', 'p' => 'PK', 'UNIQUE' => 'UK', 'u' => 'UK', 'FOREIGN KEY' => 'FK', 'f' => 'FK' }[r['ctype']]
          k[:keys] |= [label] if label
          k[:ref] = "#{r['rtable']}.#{r['rcolumn']}" if label == 'FK' && r['rtable']
        end
        columns = Hash.new { |h, k| h[k] = [] }
        fetch(c, mariadb? ? MY_COLUMNS : PG_COLUMNS).each do |r|
          k = keys.fetch([r['tname'], r['cname']], { keys: [], ref: nil })
          columns[r['tname']] << { name: r['cname'], type: r['ctype'], nullable: %w(YES t true).include?(r['cnull'].to_s),
                                   default: (r['cdefault'] unless mariadb? && r['cdefault'] == 'NULL'), keys: k[:keys].sort_by { |x| %w(PK UK FK).index(x) }, ref: k[:ref],
                                   comment: r['ccomment'].presence, position: r['cpos'].to_i }
        end
        columns.default_proc = nil
        all.select { |t| t[:sequence] }.each { |t| columns.delete(t[:name]) }
        result = { tables: tables, columns: columns, flavor: flavor, kinds: KINDS[flavor] }
        result[:objects] = fetch_objects(c, flavor, tables, all.select { |t| t[:sequence] }) if objects
        result
      end
    end

    private

    def mariadb?
      @server.adapter == 'mariadb'
    end

    def fetch_objects(c, flavor, tables, my_sequences)
      flavor == 'postgresql' ? pg_objects(c, tables) : my_objects(c, flavor, my_sequences)
    end

    # 권한이 없어 못 읽는 목록은 빈 목록 (화면에서 필요한 권한 안내)
    def safe_fetch(c, sql)
      fetch(c, sql)
    rescue StandardError
      []
    end

    def text(v)
      v.is_a?(String) ? v.dup.force_encoding('UTF-8').scrub : v
    end

    def my_objects(c, flavor, my_sequences)
      views = safe_fetch(c, MY_VIEWS).map do |r|
        { key: r['tname'], name: r['tname'], definition: text(r['vdef']).presence,
          updatable: r['upd'], check: r['chk'], security: r['sec'], definer: r['definer'] }
      end
      params = safe_fetch(c, MY_PARAMS).group_by { |r| [r['rtype'], r['name']] }
      routines = safe_fetch(c, MY_ROUTINES).map do |r|
        args = (params[[r['rtype'], r['name']]] || []).map do |p|
          [(r['rtype'] == 'PROCEDURE' ? p['pmode'] : nil), p['pname'], p['ptype']].compact.join(' ')
        end.join(', ')
        { key: r['name'], name: r['name'], kind: r['rtype'] == 'FUNCTION' ? 'function' : 'procedure', args: args,
          returns: r['rtype'] == 'FUNCTION' ? r['returns'] : nil, comment: text(r['comment']).presence,
          definition: text(r['def']).presence, security: r['sec'], definer: r['definer'],
          access: r['access'], deterministic: r['det'], created: tm(r['created']), altered: tm(r['altered']) }
      end
      triggers = safe_fetch(c, MY_TRIGGERS).map do |r|
        { key: r['name'], name: r['name'], table: r['tbl'], timing: "#{r['timing']} #{r['evt']}", status: 'ENABLED',
          definition: text(r['def']).presence, definer: r['definer'], created: tm(r['created']) }
      end
      # 이벤트(DB 잡): information_schema 는 EVENT 권한이 있어야 보임 → MariaDB 는 mysql.event 를 읽기 권한으로 대신 조회
      ev = safe_fetch(c, MY_EVENTS)
      ev = safe_fetch(c, MY_EVENTS_TABLE) if ev.empty? && flavor == 'mariadb'
      events = ev.map do |r|
        schedule = if r['etype'].to_s.start_with?('ONE')
                     "1회 · #{tm(r['at_time'])}"
                   else
                     "매 #{r['ival']}#{INTERVALS.fetch(r['ifield'].to_s, " #{r['ifield']}")}#{" · #{tm(r['starts'])} 부터" if r['starts']}"
                   end
        { key: r['name'], name: text(r['name']), schedule: schedule, status: r['status'], last_run: tm(r['last_run']),
          comment: text(r['comment']).presence, definition: text(r['def']).presence, definer: r['definer'],
          ends: tm(r['ends']), on_completion: r['oncomp'] }
      end
      sequences = my_sequences.map do |t|
        row = begin
          c.query("SELECT * FROM #{quote_my(@schema)}.#{quote_my(t[:name])}").first || {}
        rescue StandardError
          {}
        end
        { key: t[:name], name: t[:name], comment: t[:comment], type: 'BIGINT', start: row['start_value'], increment: row['increment'],
          min: row['minimum_value'], max: row['maximum_value'], cycle: row['cycle_option'].to_i == 1, cache: row['cache_size'] }
      end
      { 'view' => views, 'function' => routines.select { |r| r[:kind] == 'function' },
        'procedure' => routines.select { |r| r[:kind] == 'procedure' }, 'trigger' => triggers, 'event' => events,
        'sequence' => (flavor == 'mariadb' ? sequences : nil) }
    end

    def pg_objects(c, tables)
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
        events = begin
          c.exec(PG_CRON).to_a.map do |r|
            { key: r['jobid'].to_s, name: r['jobname'].presence || "job #{r['jobid']}", schedule: r['schedule'],
              status: r['active'] == 't' ? 'ENABLED' : 'DISABLED', definition: r['command'], definer: r['username'] }
          end
        rescue StandardError
          []
        end
      end
      { 'view' => views.reject { |v| v[:matview] }, 'matview' => views.select { |v| v[:matview] },
        'function' => routines.select { |r| r[:kind] == 'function' }, 'procedure' => routines.select { |r| r[:kind] == 'procedure' },
        'trigger' => triggers, 'sequence' => sequences, 'event' => events }
    end

    # DB 시각은 DB 서버 기준 그대로 (시간대 표기 없이)
    def tm(value)
      value.respond_to?(:strftime) ? value.strftime('%Y-%m-%d %H:%M') : value
    end

    def quote_my(name)
      "`#{name.to_s.gsub('`', '``')}`"
    end

    def fetch(conn, sql)
      if mariadb?
        conn.prepare(sql).execute(@schema).to_a
      else
        conn.exec_params(sql, [@schema]).to_a
      end
    end

    # SSH 터널을 쓰면 터널 안쪽(127.0.0.1:임시 포트)으로 접속, 첫 연결 때 SSH 서버 지문을 저장
    def connect(&block)
      return direct(@server.host, @server.port, &block) unless @server.ssh_enabled?
      Tunnel.open(@server) do |host, port, fingerprint|
        result = direct(host, port, &block)
        if @server.persisted? && @server.ssh_host_key.blank? && fingerprint
          @server.update_column(:ssh_host_key, fingerprint)
        end
        @fingerprint = fingerprint
        result
      end
    rescue DbManage::Error
      raise
    rescue LoadError
      raise Error, 'SSH 라이브러리를 불러올 수 없습니다. 관리자에게 문의하세요.'
    rescue StandardError => e
      raise Error, "SSH 터널 실패: #{e.message.to_s.lines.first.to_s.strip.truncate(200)}"
    end

    public

    # 연결 시험 때 보여 줄 SSH 서버 지문
    attr_reader :fingerprint

    private

    def direct(host, port)
      conn = mariadb? ? open_mariadb(host, port) : open_postgresql(host, port)
      yield conn
    rescue DbManage::Error
      raise
    rescue LoadError
      raise Error, 'DB 드라이버를 불러올 수 없습니다. 관리자에게 문의하세요.'
    rescue StandardError => e
      raise Error, "DB 연결·조회 실패: #{e.message.to_s.lines.first.to_s.strip.truncate(300)}"
    ensure
      begin
        conn&.close
      rescue StandardError
        nil
      end
    end

    def open_mariadb(host, port)
      require 'mysql2'
      t = @server.timeout
      c = Mysql2::Client.new(host: host, port: port, username: @server.username, password: @server.password,
                             database: @server.database_name, connect_timeout: t, read_timeout: t * 3, write_timeout: t,
                             encoding: 'utf8mb4', reconnect: false)
      c.query('SET SESSION TRANSACTION READ ONLY')
      c
    end

    def open_postgresql(host, port)
      require 'pg'
      t = @server.timeout
      PG.connect(host: host, port: port, dbname: @server.database_name, user: @server.username,
                 password: @server.password, connect_timeout: t, sslmode: 'prefer', application_name: 'redmine_db_manage',
                 options: "-c statement_timeout=#{t * 3000} -c default_transaction_read_only=on")
    end

    MY_TABLES = <<~SQL.freeze
      SELECT TABLE_NAME AS tname, TABLE_COMMENT AS tcomment, TABLE_ROWS AS trows, TABLE_TYPE AS ttype
      FROM information_schema.TABLES WHERE TABLE_SCHEMA = ? ORDER BY TABLE_NAME
    SQL
    MY_COLUMNS = <<~SQL.freeze
      SELECT TABLE_NAME AS tname, COLUMN_NAME AS cname, COLUMN_TYPE AS ctype, IS_NULLABLE AS cnull,
             COLUMN_DEFAULT AS cdefault, COLUMN_COMMENT AS ccomment, ORDINAL_POSITION AS cpos
      FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = ? ORDER BY TABLE_NAME, ORDINAL_POSITION
    SQL
    MY_KEYS = <<~SQL.freeze
      SELECT k.TABLE_NAME AS tname, k.COLUMN_NAME AS cname, t.CONSTRAINT_TYPE AS ctype,
             k.REFERENCED_TABLE_NAME AS rtable, k.REFERENCED_COLUMN_NAME AS rcolumn
      FROM information_schema.KEY_COLUMN_USAGE k
      JOIN information_schema.TABLE_CONSTRAINTS t
        ON t.CONSTRAINT_SCHEMA = k.CONSTRAINT_SCHEMA AND t.TABLE_NAME = k.TABLE_NAME AND t.CONSTRAINT_NAME = k.CONSTRAINT_NAME
      WHERE k.TABLE_SCHEMA = ?
    SQL
    INTERVALS = { 'YEAR' => '년', 'QUARTER' => '분기', 'MONTH' => '개월', 'WEEK' => '주', 'DAY' => '일', 'HOUR' => '시간',
                  'MINUTE' => '분', 'SECOND' => '초', 'DAY_HOUR' => '일 시간', 'HOUR_MINUTE' => '시간 분' }.freeze
    MY_VIEWS = <<~SQL.freeze
      SELECT TABLE_NAME AS tname, VIEW_DEFINITION AS vdef, IS_UPDATABLE AS upd, CHECK_OPTION AS chk,
             SECURITY_TYPE AS sec, DEFINER AS definer
      FROM information_schema.VIEWS WHERE TABLE_SCHEMA = ? ORDER BY TABLE_NAME
    SQL
    MY_ROUTINES = <<~SQL.freeze
      SELECT ROUTINE_NAME AS name, ROUTINE_TYPE AS rtype, DTD_IDENTIFIER AS returns, ROUTINE_COMMENT AS comment,
             ROUTINE_DEFINITION AS def, SECURITY_TYPE AS sec, DEFINER AS definer, SQL_DATA_ACCESS AS access,
             IS_DETERMINISTIC AS det, CREATED AS created, LAST_ALTERED AS altered
      FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = ? ORDER BY ROUTINE_NAME
    SQL
    MY_PARAMS = <<~SQL.freeze
      SELECT SPECIFIC_NAME AS name, ROUTINE_TYPE AS rtype, ORDINAL_POSITION AS pos, PARAMETER_MODE AS pmode,
             PARAMETER_NAME AS pname, DTD_IDENTIFIER AS ptype
      FROM information_schema.PARAMETERS WHERE SPECIFIC_SCHEMA = ? AND ORDINAL_POSITION > 0 ORDER BY SPECIFIC_NAME, ORDINAL_POSITION
    SQL
    MY_TRIGGERS = <<~SQL.freeze
      SELECT TRIGGER_NAME AS name, EVENT_OBJECT_TABLE AS tbl, ACTION_TIMING AS timing, EVENT_MANIPULATION AS evt,
             ACTION_STATEMENT AS def, DEFINER AS definer, CREATED AS created
      FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA = ? ORDER BY TRIGGER_NAME
    SQL
    MY_EVENTS = <<~SQL.freeze
      SELECT EVENT_NAME AS name, EVENT_TYPE AS etype, EXECUTE_AT AS at_time, INTERVAL_VALUE AS ival, INTERVAL_FIELD AS ifield,
             STARTS AS starts, ENDS AS ends, STATUS AS status, LAST_EXECUTED AS last_run, EVENT_COMMENT AS comment,
             EVENT_DEFINITION AS def, DEFINER AS definer, ON_COMPLETION AS oncomp
      FROM information_schema.EVENTS WHERE EVENT_SCHEMA = ? ORDER BY EVENT_NAME
    SQL
    MY_EVENTS_TABLE = <<~SQL.freeze
      SELECT name, IF(execute_at IS NULL, 'RECURRING', 'ONE TIME') AS etype, execute_at AS at_time, interval_value AS ival,
             interval_field AS ifield, starts, ends, status, last_executed AS last_run, comment, body AS def, definer,
             on_completion AS oncomp
      FROM mysql.event WHERE db = ? ORDER BY name
    SQL
    PG_VIEWS = <<~SQL.freeze
      SELECT c.relname AS tname, c.relkind AS kind, pg_get_viewdef(c.oid, true) AS vdef, pg_get_userbyid(c.relowner) AS owner
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = $1 AND c.relkind IN ('v', 'm') ORDER BY c.relname
    SQL
    # 확장(pgcrypto 등)이 만든 함수는 빼고, C·internal 함수는 정의를 읽지 않음
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
  end
end
