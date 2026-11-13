# DB 종류별 접속·조회 공통 (DialectMysql · DialectPostgresql · DialectMssql · DialectOracle 이 이어받음)
# 각 DB 는 아래 메서드로 "같은 모양"의 결과를 돌려줌 — Connector 가 화면용 스냅샷으로 합침
#   open(host, port) / close(conn) / version(conn) / flavor(conn)
#   tables(conn)  → [{ name:, comment:, rows:, view:, matview:, sequence: }]
#   columns(conn) → [{ table:, name:, type:, nullable:, default:, comment:, position: }]
#   keys(conn)    → [{ table:, column:, type: 'PK'|'UK'|'FK', rtable:, rcolumn: }]
#   indexes(conn) → [{ table:, name:, unique:, primary:, columns: [..], method: }]
#   objects(conn, flavor, sequence_tables) → { 종류 => [..] | nil }
#   select(conn, sql, limit, seconds) → { columns: [..], rows: [[..]], truncated: }   (SQL 조회, 읽기 전용)
module DbManage
  class DialectBase
    def initialize(server, schema)
      @server = server
      @schema = schema
    end

    attr_reader :schema

    def close(conn)
      conn&.close
    rescue StandardError
      nil
    end

    # 이관용 쓰기 계정 (비우면 조회 계정)
    def write_user
      @server.write_account? ? [@server.write_username, @server.write_password] : [@server.username, @server.password]
    end

    def indexes(_conn)
      []
    end

    private

    # 권한이 없어 못 읽는 목록은 빈 목록 (화면에서 필요한 권한 안내)
    def safe(default = [])
      yield
    rescue StandardError
      default
    end

    def text(v)
      v.is_a?(String) ? v.dup.force_encoding('UTF-8').scrub : v
    end

    # DB 시각은 DB 서버 기준 그대로 (시간대 표기 없이)
    def tm(value)
      value.respond_to?(:strftime) ? value.strftime('%Y-%m-%d %H:%M') : value
    end

    def cell(v)
      case v
      when nil then nil
      when String then text(v)
      when Time, DateTime then v.strftime('%Y-%m-%d %H:%M:%S')
      when Date then v.strftime('%Y-%m-%d')
      when BigDecimal then v.to_s('F')
      else v
      end
    end
  end
end
