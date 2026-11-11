# 원격 DB 에 읽기 전용으로 접속해 테이블·컬럼·키 정보(메타데이터)만 읽음 — 데이터 조회·변경 SQL 은 실행하지 않음
# - MariaDB·MySQL: mysql2 (세션을 READ ONLY 로), PostgreSQL: pg (default_transaction_read_only=on)
# - 결과 형식은 DB 종류와 관계없이 같음
#   tables:  [{ name:, comment:, rows:, view: }]
#   columns: { 테이블명 => [{ name:, type:, nullable:, default:, keys: ['PK','UK','FK'], ref:, comment:, position: }] }
module DbManage
  class Error < StandardError; end

  class Connector
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

    # 스키마 전체 (테이블 목록 + 컬럼 + 키) 한 번에
    def snapshot
      connect do |c|
        tables = fetch(c, mariadb? ? MY_TABLES : PG_TABLES).map do |r|
          rows = r['trows'].to_i
          view = r['ttype'].to_s.match?(/VIEW|\Av\z|\Am\z/)
          # MariaDB 는 뷰 설명에 'VIEW' 를 넣어 줌 → 빈 설명으로
          comment = r['tcomment'].presence unless view && r['tcomment'] == 'VIEW'
          { name: r['tname'], comment: comment, rows: view || rows.negative? ? nil : rows, view: view }
        end
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
        { tables: tables, columns: columns }
      end
    end

    private

    def mariadb?
      @server.adapter == 'mariadb'
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
