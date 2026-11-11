# 원격 DB 에 읽기 전용으로 접속해 테이블·컬럼·키·인덱스(메타데이터)를 읽음. SQL 조회는 따로 권한·제한을 둔 select 만
# - DB 종류별 처리는 Dialect* (dialect_mysql·postgresql·mssql·oracle) — 결과 형식은 DB 종류와 관계없이 같음
#   tables:  [{ name:, comment:, rows:, view:, matview: }]
#   columns: { 테이블명 => [{ name:, type:, nullable:, default:, keys: ['PK','UK','FK','IX'], ref:, comment:, position: }] }
#   indexes: { 테이블명 => [{ name:, unique:, primary:, columns: [..], method: }] }
#   objects (snapshot(objects: true) 일 때): { 종류 => [{ key:, name:, ... , definition: }] } — 종류는 DB 마다 다름 (KINDS)
#   종류 목록이 nil 이면 그 DB 에 없는 기능(예: pg_cron 없는 PostgreSQL 의 DB 잡)
# - SSH 터널(여러 단계 경유 가능)을 쓰면 터널 안쪽으로 접속 (Tunnel)
module DbManage
  class Error < StandardError; end

  class Connector
    # DB 종류별 탭 (조사: MariaDB 10.11 · MySQL 8.4 · PostgreSQL 17 · SQL Server · Oracle)
    KINDS = {
      'mariadb' => %w(table view function procedure trigger event sequence),
      'mysql' => %w(table view function procedure trigger event),
      'postgresql' => %w(table view matview function procedure trigger sequence event),
      'mssql' => %w(table view function procedure trigger sequence synonym event),
      'oracle' => %w(table view matview function procedure package trigger sequence synonym event)
    }.freeze
    DIALECTS = { 'mariadb' => 'DialectMysql', 'postgresql' => 'DialectPostgresql', 'mssql' => 'DialectMssql', 'oracle' => 'DialectOracle' }.freeze
    DEFAULT_SCHEMA = { 'postgresql' => 'public', 'mssql' => 'dbo' }.freeze

    def self.default_schema(server)
      return server.username.to_s.upcase if server.adapter == 'oracle'
      DEFAULT_SCHEMA[server.adapter] || server.database_name
    end

    def initialize(server, schema = nil)
      @server = server
      @schema = schema.presence || self.class.default_schema(server)
      @dialect = DbManage.const_get(DIALECTS.fetch(server.adapter)).new(server, @schema)
    end

    attr_reader :schema, :fingerprint

    # 연결 시험: DB 버전 문자열
    def version
      connect { |c| @dialect.version(c) }
    end

    # 스키마 전체 한 번에. objects: true 면 뷰 정의·함수·프로시저·트리거·DB 잡·시퀀스 등도
    def snapshot(objects: false)
      connect do |c|
        flavor = @dialect.flavor(c)
        all = @dialect.tables(c)
        tables = all.reject { |t| t[:sequence] }.map { |t| t.except(:sequence) }
        names = tables.map { |t| t[:name] }.to_set
        keys = Hash.new { |h, k| h[k] = { keys: [], ref: nil } }
        @dialect.keys(c).each do |k|
          e = keys[[k[:table], k[:column]]]
          e[:keys] |= [k[:type]]
          e[:ref] = "#{k[:rtable]}.#{k[:rcolumn]}" if k[:type] == 'FK' && k[:rtable]
        end
        indexes = @dialect.indexes(c).select { |i| names.include?(i[:table]) }.group_by { |i| i[:table] }
                          .transform_values { |l| l.map { |i| i.except(:table) }.sort_by { |i| [i[:primary] ? 0 : 1, i[:name].to_s] } }
        indexed = indexes.flat_map { |t, l| l.flat_map { |i| i[:columns].map { |col| [t, col] } } }.to_set
        columns = Hash.new { |h, k| h[k] = [] }
        @dialect.columns(c).each do |col|
          next unless names.include?(col[:table])
          k = keys.fetch([col[:table], col[:name]], { keys: [], ref: nil })
          ks = k[:keys].sort_by { |x| %w(PK UK FK).index(x) }
          ks += ['IX'] if ks.empty? && indexed.include?([col[:table], col[:name]])
          columns[col[:table]] << col.except(:table).merge(keys: ks, ref: k[:ref])
        end
        columns.default_proc = nil
        result = { tables: tables, columns: columns, indexes: indexes, flavor: flavor, kinds: KINDS[flavor], schema: @schema,
                   read_at: Time.now }
        result[:objects] = @dialect.objects(c, flavor, all.select { |t| t[:sequence] }) if objects
        result
      end
    end

    # SQL 조회 (읽기 전용 트랜잭션·시간 제한·건수 제한은 Dialect 가 처리)
    def select(sql, limit:, seconds:)
      connect { |c| @dialect.select(c, sql, limit, seconds) }
    end

    private

    # SSH 터널을 쓰면 터널 안쪽(127.0.0.1:임시 포트)으로 접속, 첫 연결 때 경유 서버마다 SSH 지문을 저장
    def connect(&block)
      return direct(@server.host, @server.port, &block) unless @server.ssh_enabled?
      Tunnel.open(@server) do |host, port, fingerprints|
        result = direct(host, port, &block)
        @fingerprint = fingerprints.compact.join(' / ')
        @server.remember_fingerprints(fingerprints) if @server.persisted?
        result
      end
    rescue DbManage::Error
      raise
    rescue LoadError
      raise Error, 'SSH 라이브러리를 불러올 수 없습니다. 관리자에게 문의하세요.'
    rescue StandardError => e
      raise Error, "SSH 터널 실패: #{e.message.to_s.lines.first.to_s.strip.truncate(200)}"
    end

    def direct(host, port)
      conn = @dialect.open(host, port)
      yield conn
    rescue DbManage::Error
      raise
    rescue LoadError
      raise Error, 'DB 드라이버를 불러올 수 없습니다. 관리자에게 문의하세요.'
    rescue StandardError => e
      raise Error, "DB 연결·조회 실패: #{e.message.to_s.lines.first.to_s.strip.truncate(300)}"
    ensure
      @dialect.close(conn)
    end
  end
end
