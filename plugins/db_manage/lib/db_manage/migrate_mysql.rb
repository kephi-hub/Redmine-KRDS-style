# 이관 엔진 — MariaDB·MySQL
# - 구조: SHOW CREATE TABLE 을 따옴표·괄호를 고려해 쪼개 칼럼·키·인덱스·외래키 정의를 비교 → CREATE / ALTER
# - 데이터: 원본 읽기 전용 세션 스트리밍(cast: false — 값은 원본 문자열 그대로, 바이너리는 X'..'), 1MB 씩 여러 행 INSERT
#   두 세션 time_zone '+00:00'(TIMESTAMP 값 그대로), 대상은 FOREIGN_KEY_CHECKS=0 · NO_AUTO_VALUE_ON_ZERO, 생성 칼럼 제외
# - 백업: DROP + CREATE + INSERT (mysql 클라이언트로 실행하면 복원)
module DbManage
  class MigrateMysql < MigrateBase
    def self.q(name)
      "`#{name.to_s.gsub('`', '``')}`"
    end

    def q(name)
      self.class.q(name)
    end

    def unq(name)
      name.to_s.gsub('``', '`')
    end

    def prepare
      c.query("USE #{q(schema)}")
      c.query('SET NAMES utf8mb4')
      c.query("SET time_zone = '+00:00'")
      return unless @write
      c.query('SET FOREIGN_KEY_CHECKS = 0')
      c.query("SET SESSION sql_mode = TRIM(BOTH ',' FROM CONCAT(@@SESSION.sql_mode, ',NO_AUTO_VALUE_ON_ZERO'))")
    end

    def exec(sql)
      c.query(sql)
    end

    def count(name)
      c.query("SELECT COUNT(*) AS n FROM #{q(name)}").first['n']
    end

    def row_estimates
      c.query('SELECT TABLE_NAME AS n, TABLE_ROWS AS r FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()').to_h { |r| [r['n'], r['r']] }
    end

    def describe(name)
      row = c.query("SHOW CREATE TABLE #{q(name)}").first
      ddl = row && (row['Create Table'] || raise(Error, t(:error_db_mig_view, name: name)))
      return nil unless ddl
      parsed = parse(ddl)
      parsed.merge(ddl: ddl, parents: parsed[:fks].values.filter_map { |d| d[/REFERENCES `((?:[^`]|``)*)`/, 1]&.then { |x| unq(x) } })
    rescue Mysql2::Error => e
      raise unless e.error_number == 1146
      nil
    end

    # SHOW CREATE TABLE → { columns: { 이름 => 정의 }, order:, pk:, indexes: { 이름 => 정의 }, fks: { 이름 => 정의 }, comment: 'SQL 문자열 그대로' }
    def parse(ddl)
      cs = ddl.chars
      i = cs.index('(') + 1
      parts = []
      buf = +''
      depth = 0
      quote = nil
      finish = cs.size
      while i < cs.size
        ch = cs[i]
        if quote
          buf << ch
          if ch == '\\' && quote != '`'
            buf << cs[i + 1].to_s
            i += 1
          elsif ch == quote
            if cs[i + 1] == quote
              buf << cs[i + 1]
              i += 1
            else
              quote = nil
            end
          end
        elsif ["'", '"', '`'].include?(ch)
          quote = ch
          buf << ch
        elsif ch == '('
          depth += 1
          buf << ch
        elsif ch == ')'
          if depth.zero?
            parts << buf.strip
            finish = i
            break
          end
          depth -= 1
          buf << ch
        elsif ch == ',' && depth.zero?
          parts << buf.strip
          buf = +''
        else
          buf << ch
        end
        i += 1
      end
      tail = cs[(finish + 1)..].to_a.join
      r = { columns: {}, order: [], pk: nil, indexes: {}, fks: {} }
      parts.reject(&:empty?).each do |p|
        if (m = p.match(/\A`((?:[^`]|``)*)`\s/))
          n = unq(m[1])
          r[:columns][n] = p
          r[:order] << n
        elsif p.start_with?('PRIMARY KEY')
          r[:pk] = p
        elsif (m = p.match(/\A(?:UNIQUE |FULLTEXT |SPATIAL )?(?:KEY|INDEX) `((?:[^`]|``)*)`/))
          r[:indexes][unq(m[1])] = p
        elsif (m = p.match(/\ACONSTRAINT `((?:[^`]|``)*)` FOREIGN KEY/))
          r[:fks][unq(m[1])] = p
        end
      end
      r[:comment] = tail[/COMMENT='((?:[^'\\]|\\.|'')*)'/m, 1]
      r
    end

    def plan(name, a, b)
      unique = a[:pk].present? || a[:indexes].values.any? { |d| d.start_with?('UNIQUE') }
      return { status: 'new', statements: [a[:ddl].sub(/\s+AUTO_INCREMENT=\d+/, '')], warnings: [], unique: unique } if b.nil?
      warnings = []
      drops = []
      alters = []
      prev = nil
      a[:order].each do |col|
        if !b[:columns].key?(col)
          alters << "ADD COLUMN #{a[:columns][col]} #{prev ? "AFTER #{q(prev)}" : 'FIRST'}"
        elsif a[:columns][col] != b[:columns][col]
          alters << "MODIFY COLUMN #{a[:columns][col]}"
        end
        prev = col
      end
      (b[:order] - a[:order]).each { |col| warnings << t(:text_db_mig_keep_col, name: col) }
      if a[:pk] != b[:pk]
        if b[:pk].nil? && a[:pk]
          alters << "ADD #{a[:pk]}"
        else
          warnings << t(:text_db_mig_pk_diff)
        end
      end
      a[:indexes].each do |n, d|
        next if b[:indexes][n] == d
        alters << "DROP INDEX #{q(n)}" if b[:indexes][n]
        alters << "ADD #{d}"
      end
      (b[:indexes].keys - a[:indexes].keys).each { |n| warnings << t(:text_db_mig_keep_index, name: n) }
      a[:fks].each do |n, d|
        next if b[:fks][n] == d
        drops << "ALTER TABLE #{q(name)} DROP FOREIGN KEY #{q(n)}" if b[:fks][n]
        alters << "ADD #{d}"
      end
      alters << "COMMENT='#{a[:comment]}'" if a[:comment] != b[:comment]
      statements = drops + (alters.any? ? ["ALTER TABLE #{q(name)}\n  #{alters.join(",\n  ")}"] : [])
      unique ||= b[:pk].present? || b[:indexes].values.any? { |d| d.start_with?('UNIQUE') }
      { status: statements.any? ? 'changed' : 'same', statements: statements, warnings: warnings, unique: unique }
    end

    def lit(v)
      return 'NULL' if v.nil?
      return (v.empty? ? "''" : "X'#{v.unpack1('H*')}'") if v.encoding == Encoding::BINARY
      "'#{c.escape(v)}'"
    end

    def column_names(conn, name)
      conn.query("SELECT COLUMN_NAME AS c, EXTRA AS x FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() " \
                 "AND TABLE_NAME = '#{conn.escape(name)}' ORDER BY ORDINAL_POSITION")
          .reject { |r| r['x'].to_s =~ /GENERATED|VIRTUAL|PERSISTENT|STORED/i }.map { |r| r['c'] }
    end

    def copy_from(src, name, mode, _sm, _tm)
      cols = column_names(src.c, name) & column_names(c, name)
      raise Error, t(:error_db_mig_no_cols) if cols.empty?
      list = cols.map { |x| q(x) }.join(', ')
      head = "#{mode == 'insert_new' ? 'INSERT IGNORE' : 'INSERT'} INTO #{q(name)} (#{list}) VALUES "
      tail = mode == 'upsert' ? " ON DUPLICATE KEY UPDATE #{cols.map { |x| "#{q(x)} = VALUES(#{q(x)})" }.join(', ')}" : ''
      n = 0
      buf = []
      bytes = 0
      c.query('START TRANSACTION')
      c.query("DELETE FROM #{q(name)}") if mode == 'replace'
      flush = lambda do
        return if buf.empty?
        c.query(head + buf.join(',') + tail)
        n += buf.size
        buf.clear
        bytes = 0
        yield n
      end
      rows = ->(&blk) { src.c.query("SELECT #{list} FROM #{q(name)}", stream: true, cache_rows: false, cast: false, as: :array).each(&blk) }
      drain(rows) do |row|
        v = "(#{row.map { |x| lit(x) }.join(',')})"
        buf << v
        bytes += v.bytesize
        flush.call if bytes >= BATCH_BYTES
      end
      flush.call
      c.query('COMMIT')
      n
    rescue StandardError
      begin
        c.query('ROLLBACK')
      rescue StandardError
        nil
      end
      raise
    end

    def backup(name, model, gz)
      n = 0
      gz.write("-- #{name} 이관 전 백업 (#{Time.current.in_time_zone('Asia/Seoul').strftime('%F %T')}) — mysql 클라이언트로 실행\n")
      gz.write("SET NAMES utf8mb4;\nSET time_zone = '+00:00';\nSET FOREIGN_KEY_CHECKS = 0;\n")
      gz.write("DROP TABLE IF EXISTS #{q(name)};\n#{model[:ddl]};\n")
      list = column_names(c, name).map { |x| q(x) }.join(', ')
      buf = []
      bytes = 0
      c.query("SELECT #{list} FROM #{q(name)}", stream: true, cache_rows: false, cast: false, as: :array).each do |row|
        v = "(#{row.map { |x| lit(x) }.join(',')})"
        buf << v
        bytes += v.bytesize
        n += 1
        next if bytes < BATCH_BYTES
        gz.write("INSERT INTO #{q(name)} (#{list}) VALUES #{buf.join(',')};\n")
        buf.clear
        bytes = 0
      end
      gz.write("INSERT INTO #{q(name)} (#{list}) VALUES #{buf.join(',')};\n") if buf.any?
      gz.write("SET FOREIGN_KEY_CHECKS = 1;\n")
      n
    end

    # ---- 뷰·함수·프로시저 ----
    def object_kinds
      %w(view function procedure)
    end

    def object_exists?(kind, key)
      sql = if kind == 'view'
              "SELECT 1 FROM information_schema.VIEWS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = '#{c.escape(key)}'"
            else
              "SELECT 1 FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_TYPE = '#{kind.upcase}' AND ROUTINE_NAME = '#{c.escape(key)}'"
            end
      c.query(sql).any?
    end

    # SHOW CREATE … (함수·프로시저 본문은 정의자이거나 mysql.proc 조회 권한이 있어야 보임)
    def object_def(kind, key)
      row = c.query("SHOW CREATE #{kind.upcase} #{q(key)}").first
      row && row[kind == 'view' ? 'Create View' : "Create #{kind.capitalize}"]
    rescue Mysql2::Error => e
      raise unless [1305, 1146, 1356].include?(e.error_number)
      nil
    end

    # 대상에서 실행할 문장 — DEFINER 는 빼고(대상 계정이 정의자가 됨) 원본 스키마 이름은 대상 스키마로
    def object_ddl(kind, key, to_schema)
      d = object_def(kind, key) or raise Error, t(:error_db_mig_obj_def)
      d = d.sub(/\s+DEFINER=`(?:[^`]|``)*`@`(?:[^`]|``)*`/, '')
      d = d.gsub("#{q(schema)}.", "#{q(to_schema)}.") if to_schema != schema
      kind == 'view' ? [d.sub(/\ACREATE\s+/, 'CREATE OR REPLACE ')] : ["DROP #{kind.upcase} IF EXISTS #{q(key)}", d]
    end

    def create_object(_kind, _key, statements)
      statements.each { |x| exec(x) }
    end

    def object_script(kind, key)
      st = object_ddl(kind, key, schema)
      head = "-- #{kind} #{key} 이관 전 백업 — mysql 클라이언트로 실행\n"
      return head + st.map { |x| "#{x};\n" }.join if kind == 'view'
      "#{head}DELIMITER $$\n#{st.map { |x| "#{x} $$\n" }.join}DELIMITER ;\n"
    rescue Error
      nil
    end
  end
end
