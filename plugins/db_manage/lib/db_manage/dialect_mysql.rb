# MariaDB · MySQL — mysql2, 세션을 READ ONLY 로
# 조회 전용 계정에 안 보이는 객체: 함수·프로시저(mysql.proc / SHOW_ROUTINE), 이벤트(mysql.event / EVENT), 트리거(TRIGGER)
module DbManage
  class DialectMysql < DialectBase
    INTERVALS = { 'YEAR' => '년', 'QUARTER' => '분기', 'MONTH' => '개월', 'WEEK' => '주', 'DAY' => '일', 'HOUR' => '시간',
                  'MINUTE' => '분', 'SECOND' => '초', 'DAY_HOUR' => '일 시간', 'HOUR_MINUTE' => '시간 분' }.freeze

    def open(host, port)
      require 'mysql2'
      t = @server.timeout
      c = Mysql2::Client.new(host: host, port: port, username: @server.username, password: @server.password,
                             database: @server.database_name, connect_timeout: t, read_timeout: t * 3, write_timeout: t,
                             encoding: 'utf8mb4', reconnect: false)
      c.query('SET SESSION TRANSACTION READ ONLY')
      c
    end

    # 이관용 쓰기 연결 — 읽기 전용 아님, 큰 ALTER·INSERT 를 기다리도록 read_timeout 넉넉히
    def open_write(host, port)
      require 'mysql2'
      t = @server.timeout
      user = @server.write_account? ? @server.write_username : @server.username
      pass = @server.write_account? ? @server.write_password : @server.password
      Mysql2::Client.new(host: host, port: port, username: user, password: pass, database: @server.database_name,
                         connect_timeout: t, read_timeout: 900, write_timeout: 300, encoding: 'utf8mb4', reconnect: false)
    end

    def version(c)
      c.query('SELECT VERSION() AS v').first['v']
    end

    def flavor(c)
      version(c).to_s.include?('MariaDB') ? 'mariadb' : 'mysql'
    end

    def tables(c)
      fetch(c, MY_TABLES).map do |r|
        rows = r['trows'].to_i
        ttype = r['ttype'].to_s
        view = ttype.include?('VIEW')
        # MariaDB 는 뷰 설명에 'VIEW' 를 넣어 줌 → 빈 설명으로
        comment = text(r['tcomment']).presence unless view && r['tcomment'] == 'VIEW'
        { name: r['tname'], comment: comment, rows: view || rows.negative? ? nil : rows, view: view, matview: false, sequence: ttype == 'SEQUENCE' }
      end
    end

    def columns(c)
      fetch(c, MY_COLUMNS).map do |r|
        { table: r['tname'], name: r['cname'], type: r['ctype'], nullable: r['cnull'].to_s == 'YES',
          default: (r['cdefault'] unless r['cdefault'] == 'NULL'), comment: text(r['ccomment']).presence, position: r['cpos'].to_i }
      end
    end

    def keys(c)
      fetch(c, MY_KEYS).filter_map do |r|
        type = { 'PRIMARY KEY' => 'PK', 'UNIQUE' => 'UK', 'FOREIGN KEY' => 'FK' }[r['ctype']]
        type && { table: r['tname'], column: r['cname'], type: type, rtable: r['rtable'], rcolumn: r['rcolumn'] }
      end
    end

    def indexes(c)
      safe do
        fetch(c, MY_INDEXES).group_by { |r| [r['tname'], r['iname']] }.map do |(t, n), list|
          { table: t, name: n, unique: list.first['nonuniq'].to_i.zero?, primary: n == 'PRIMARY', method: list.first['itype'],
            columns: list.sort_by { |r| r['seq'].to_i }.map { |r| r['sub'] ? "#{r['cname']}(#{r['sub']})" : r['cname'] } }
        end
      end
    end

    # SQL 조회: 읽기 전용 트랜잭션 + 실행 시간 제한, sql_select_limit 로 limit+1 건까지만 받음
    def select(c, sql, limit, seconds)
      maria = c.server_info[:version].to_s.include?('MariaDB')
      c.query(maria ? "SET SESSION max_statement_time = #{seconds}" : "SET SESSION max_execution_time = #{seconds * 1000}")
      c.query("SET SESSION sql_select_limit = #{limit + 1}")
      c.query('START TRANSACTION READ ONLY')
      res = c.query(sql, as: :array)
      cols = res.respond_to?(:fields) ? (res.fields || []) : []
      rows = res.respond_to?(:to_a) ? res.to_a : []
      { columns: cols, rows: rows.first(limit).map { |row| row.map { |v| cell(v) } }, truncated: rows.size > limit }
    ensure
      begin
        c.query('ROLLBACK')
        c.query('SET SESSION sql_select_limit = DEFAULT')
      rescue StandardError
        nil
      end
    end

    def objects(c, flavor, seq_tables)
      views = safe { fetch(c, MY_VIEWS) }.map do |r|
        { key: r['tname'], name: r['tname'], definition: text(r['vdef']).presence,
          updatable: r['upd'], check: r['chk'], security: r['sec'], definer: r['definer'] }
      end
      params = safe { fetch(c, MY_PARAMS) }.group_by { |r| [r['rtype'], r['name']] }
      routines = safe { fetch(c, MY_ROUTINES) }.map do |r|
        args = (params[[r['rtype'], r['name']]] || []).map do |p|
          [(r['rtype'] == 'PROCEDURE' ? p['pmode'] : nil), p['pname'], p['ptype']].compact.join(' ')
        end.join(', ')
        { key: r['name'], name: r['name'], kind: r['rtype'] == 'FUNCTION' ? 'function' : 'procedure', args: args,
          returns: r['rtype'] == 'FUNCTION' ? r['returns'] : nil, comment: text(r['comment']).presence,
          definition: text(r['def']).presence, security: r['sec'], definer: r['definer'],
          access: r['access'], deterministic: r['det'], created: tm(r['created']), altered: tm(r['altered']) }
      end
      triggers = safe { fetch(c, MY_TRIGGERS) }.map do |r|
        { key: r['name'], name: r['name'], table: r['tbl'], timing: "#{r['timing']} #{r['evt']}", status: 'ENABLED',
          definition: text(r['def']).presence, definer: r['definer'], created: tm(r['created']) }
      end
      # 이벤트(DB 잡): information_schema 는 EVENT 권한이 있어야 보임 → MariaDB 는 mysql.event 를 읽기 권한으로 대신 조회
      ev = safe { fetch(c, MY_EVENTS) }
      ev = safe { fetch(c, MY_EVENTS_TABLE) } if ev.empty? && flavor == 'mariadb'
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
      sequences = seq_tables.map do |t|
        row = safe({}) { c.query("SELECT * FROM #{quote(@schema)}.#{quote(t[:name])}").first || {} }
        { key: t[:name], name: t[:name], comment: t[:comment], type: 'BIGINT', start: row['start_value'], increment: row['increment'],
          min: row['minimum_value'], max: row['maximum_value'], cycle: row['cycle_option'].to_i == 1, cache: row['cache_size'] }
      end
      { 'view' => views, 'function' => routines.select { |r| r[:kind] == 'function' },
        'procedure' => routines.select { |r| r[:kind] == 'procedure' }, 'trigger' => triggers, 'event' => events,
        'sequence' => (flavor == 'mariadb' ? sequences : nil) }
    end

    private

    def quote(name)
      "`#{name.to_s.gsub('`', '``')}`"
    end

    # 준비문(prepare/execute, 바이너리 프로토콜)은 SSH 터널(net-ssh 포트 전달)을 거치면 응답을 못 받고 read_timeout 까지 멈춤
    # (연결 시험·SQL 조회는 일반 쿼리라 통과) → 스키마 이름을 이스케이프해 일반 쿼리로
    def fetch(conn, sql)
      conn.query(sql.sub('?', "'#{conn.escape(@schema.to_s)}'")).to_a
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
    MY_INDEXES = <<~SQL.freeze
      SELECT TABLE_NAME AS tname, INDEX_NAME AS iname, NON_UNIQUE AS nonuniq, SEQ_IN_INDEX AS seq, COLUMN_NAME AS cname,
             SUB_PART AS sub, INDEX_TYPE AS itype
      FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = ? ORDER BY TABLE_NAME, INDEX_NAME, SEQ_IN_INDEX
    SQL
  end
end
