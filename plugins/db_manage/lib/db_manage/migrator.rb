# DB 이관 (MariaDB·MySQL ↔ 같은 종류) — 원본 DB 의 테이블 구조·데이터를 대상 DB 로
# - 구조: 원본 SHOW CREATE TABLE 기준. 대상에 없으면 CREATE TABLE, 있으면 ALTER TABLE 로 칼럼 추가·변경, 인덱스·외래키 추가·변경, 설명
#         대상에만 있는 칼럼·인덱스·테이블은 지우지 않고 알려 줌. 기본키가 다르면 바꾸지 않음(경고)
# - 데이터: replace(대상 비우고 전체), upsert(PK·UK 기준 추가·갱신), insert_new(없는 행만 추가) — 테이블마다 트랜잭션
#   원본은 읽기 전용 세션에서 스트리밍(cast: false — 값은 원본 문자열 그대로, 바이너리는 X'..'), 1MB 씩 여러 행 INSERT
#   두 세션 모두 time_zone '+00:00'(TIMESTAMP 값 그대로), 대상은 FOREIGN_KEY_CHECKS=0 · NO_AUTO_VALUE_ON_ZERO
# - 실행 전 바뀔 대상 테이블을 PMS 서버에 백업 (files/db_migrate/<프로젝트>/<이관 id>/<테이블>.sql.gz — 그대로 실행하면 복원)
require 'zlib'
require 'fileutils'

module DbManage
  module Migrator
    module_function

    MODES = %w(skip structure replace upsert insert_new).freeze
    DATA_MODES = %w(replace upsert insert_new).freeze
    BATCH_BYTES = 1_000_000
    BIG_ROWS = 1_000_000
    KEEP_BACKUPS = 20

    def q(name)
      "`#{name.to_s.gsub('`', '``')}`"
    end

    def unq(name)
      name.to_s.gsub('``', '`')
    end

    def backup_root
      Pathname.new(Redmine::Configuration['attachments_storage_path'].presence || Rails.root.join('files').to_s).join('db_migrate')
    end

    # 1차는 MariaDB·MySQL 끼리만
    def supported?(source, target)
      source&.db_server&.adapter == 'mariadb' && target&.db_server&.adapter == 'mariadb' && source.id != target.id
    end

    # ---- SHOW CREATE TABLE 해석 ----
    # → { columns: { 이름 => 정의 }, order: [이름..], pk: 정의, indexes: { 이름 => 정의 }, fks: { 이름 => 정의 }, comment: 'SQL 문자열 그대로' }
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

    # 테이블 하나의 구조 변경 계획 → { status: new|changed|same, statements: [SQL..], warnings: [..], unique: 대상에 PK·UK 가 생기는지 }
    def table_plan(name, src_ddl, tgt_ddl)
      a = parse(src_ddl)
      unique = a[:pk].present? || a[:indexes].values.any? { |d| d.start_with?('UNIQUE') }
      return { status: 'new', statements: [src_ddl.sub(/\s+AUTO_INCREMENT=\d+/, '')], warnings: [], unique: unique } if tgt_ddl.nil?
      b = parse(tgt_ddl)
      warnings = []
      drops = []
      alters = []
      prev = nil
      a[:order].each do |c|
        if !b[:columns].key?(c)
          alters << "ADD COLUMN #{a[:columns][c]} #{prev ? "AFTER #{q(prev)}" : 'FIRST'}"
        elsif a[:columns][c] != b[:columns][c]
          alters << "MODIFY COLUMN #{a[:columns][c]}"
        end
        prev = c
      end
      (b[:order] - a[:order]).each { |c| warnings << I18n.t(:text_db_mig_keep_col, name: c) }
      if a[:pk] != b[:pk]
        if b[:pk].nil? && a[:pk]
          alters << "ADD #{a[:pk]}"
        else
          warnings << I18n.t(:text_db_mig_pk_diff)
        end
      end
      a[:indexes].each do |n, d|
        next if b[:indexes][n] == d
        alters << "DROP INDEX #{q(n)}" if b[:indexes][n]
        alters << "ADD #{d}"
      end
      (b[:indexes].keys - a[:indexes].keys).each { |n| warnings << I18n.t(:text_db_mig_keep_index, name: n) }
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

    def show_create(conn, name)
      row = conn.query("SHOW CREATE TABLE #{q(name)}").first
      row && (row['Create Table'] || raise(Error, I18n.t(:error_db_mig_view, name: name)))
    rescue Mysql2::Error => e
      raise unless e.error_number == 1146
      nil
    end

    def prepare(conn, schema, write: false)
      conn.query("USE #{q(schema)}")
      conn.query("SET NAMES utf8mb4")
      conn.query("SET time_zone = '+00:00'")
      return unless write
      conn.query('SET FOREIGN_KEY_CHECKS = 0')
      conn.query("SET SESSION sql_mode = TRIM(BOTH ',' FROM CONCAT(@@SESSION.sql_mode, ',NO_AUTO_VALUE_ON_ZERO'))")
    end

    # 미리보기 — 고른 테이블마다 계획 (대상은 읽기 연결로 확인)
    # choices: [{ 'table' =>, 'mode' => }] → [{ table:, mode:, status:, statements:, warnings:, rows:, error: }]
    def preview(source, target, choices)
      src_rows = {}
      out = []
      source.connector.session do |s, _|
        prepare(s, source.schema)
        s.query("SELECT TABLE_NAME AS n, TABLE_ROWS AS r FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()").each { |r| src_rows[r['n']] = r['r'] }
        ddls = choices.to_h { |c| [c['table'], show_create(s, c['table'])] }
        target.connector.session do |t, _|
          prepare(t, target.schema)
          choices.each do |c|
            item = { table: c['table'], mode: c['mode'], rows: src_rows[c['table']] }
            begin
              raise Error, I18n.t(:error_db_mig_no_source) unless ddls[c['table']]
              plan = table_plan(c['table'], ddls[c['table']], show_create(t, c['table']))
              item.merge!(plan.slice(:status, :statements, :warnings))
              item[:error] = I18n.t(:error_db_mig_no_unique) if c['mode'] == 'upsert' && !plan[:unique]
              item[:warnings] += [I18n.t(:text_db_mig_big, rows: item[:rows])] if DATA_MODES.include?(c['mode']) && item[:rows].to_i >= BIG_ROWS
            rescue StandardError => e
              item[:error] = e.message.to_s.truncate(300)
            end
            out << item
          end
        end
      end
      out
    end

    # ---- 실행 (MigrateJob) ----
    def run!(mig)
      results = []
      mig.update!(status: 'running', started_at: Time.current)
      source = mig.source_link
      target = mig.target_link
      raise Error, I18n.t(:error_db_mig_link_gone) unless source && target && supported?(source, target)
      dir = backup_root.join(mig.project_id.to_s, mig.id.to_s)
      ActiveRecord::Base.connection_pool.release_connection
      source.connector.session do |s, _|
        prepare(s, source.schema)
        target.connector.session(write: true) do |t, _|
          prepare(t, target.schema, write: true)
          mig.plan_list.each do |c|
            r = { 'table' => c['table'], 'mode' => c['mode'], 'status' => 'running' }
            results << r
            save(mig, results, force: true)
            t0 = Time.now
            begin
              run_table(mig, s, t, c['table'], c['mode'], dir, r) { save(mig, results) }
              r['status'] = 'done'
            rescue StandardError => e
              r['status'] = 'failed'
              r['error'] = e.message.to_s.dup.force_encoding('UTF-8').scrub.truncate(500)
            end
            r['seconds'] = (Time.now - t0).round(1)
            save(mig, results, force: true)
          end
        end
      end
      ok = results.count { |r| r['status'] == 'done' }
      mig.update!(status: ok == results.size ? 'done' : (ok.zero? ? 'failed' : 'partial'), finished_at: Time.current, results: results)
    rescue StandardError => e
      Rails.logger.error("[db_migrate] #{mig.id}: #{e.class} #{e.message}")
      mig.update!(status: 'failed', finished_at: Time.current, results: results, error: e.message.to_s.truncate(1000))
    ensure
      clear_cache(mig.target_link) if mig.target_link
      prune(mig.project_id)
    end

    def run_table(mig, s, t, name, mode, dir, r)
      src_ddl = show_create(s, name) or raise Error, I18n.t(:error_db_mig_no_source)
      tgt_ddl = show_create(t, name)
      plan = table_plan(name, src_ddl, tgt_ddl)
      r['plan'] = plan[:status]
      r['warnings'] = plan[:warnings]
      data = DATA_MODES.include?(mode)
      raise Error, I18n.t(:error_db_mig_no_unique) if mode == 'upsert' && !plan[:unique]
      if tgt_ddl && (plan[:statements].any? || data)
        FileUtils.mkdir_p(dir)
        file = dir.join("#{name.gsub(/[^\w.-]/, '_')}.sql.gz")
        r['backup_rows'] = backup_table(t, name, tgt_ddl, file)
        r['backup'] = file.basename.to_s
        r['backup_bytes'] = File.size(file)
        yield
      end
      plan[:statements].each { |sql| t.query(sql) }
      r['ddl'] = plan[:statements]
      return unless data
      r['rows'] = copy_data(s, t, name, mode) do |n|
        r['rows'] = n
        yield
      end
      r['target_rows'] = t.query("SELECT COUNT(*) AS n FROM #{q(name)}").first['n']
    end

    def lit(conn, v)
      return 'NULL' if v.nil?
      return (v.empty? ? "''" : "X'#{v.unpack1('H*')}'") if v.encoding == Encoding::BINARY
      "'#{conn.escape(v)}'"
    end

    def column_names(conn, name)
      conn.query("SELECT COLUMN_NAME AS c, EXTRA AS x FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() " \
                 "AND TABLE_NAME = '#{conn.escape(name)}' ORDER BY ORDINAL_POSITION")
          .reject { |r| r['x'].to_s =~ /GENERATED|VIRTUAL|PERSISTENT|STORED/i }.map { |r| r['c'] }
    end

    # 원본을 끝까지 읽어야 같은 연결을 다시 쓸 수 있으므로, 대상 쪽에서 실패해도 남은 행은 읽고 버린 뒤 오류를 올림
    def copy_data(s, t, name, mode)
      cols = column_names(s, name) & column_names(t, name)
      raise Error, I18n.t(:error_db_mig_no_cols) if cols.empty?
      list = cols.map { |c| q(c) }.join(', ')
      head = "#{mode == 'insert_new' ? 'INSERT IGNORE' : 'INSERT'} INTO #{q(name)} (#{list}) VALUES "
      tail = mode == 'upsert' ? " ON DUPLICATE KEY UPDATE #{cols.map { |c| "#{q(c)} = VALUES(#{q(c)})" }.join(', ')}" : ''
      n = 0
      buf = []
      bytes = 0
      failure = nil
      t.query('START TRANSACTION')
      t.query("DELETE FROM #{q(name)}") if mode == 'replace'
      flush = lambda do
        return if buf.empty?
        t.query(head + buf.join(',') + tail)
        n += buf.size
        buf.clear
        bytes = 0
        yield n
      end
      s.query("SELECT #{list} FROM #{q(name)}", stream: true, cache_rows: false, cast: false, as: :array).each do |row|
        next if failure
        begin
          v = "(#{row.map { |x| lit(t, x) }.join(',')})"
          buf << v
          bytes += v.bytesize
          flush.call if bytes >= BATCH_BYTES
        rescue StandardError => e
          failure = e
        end
      end
      raise failure if failure
      flush.call
      t.query('COMMIT')
      n
    rescue StandardError
      begin
        t.query('ROLLBACK')
      rescue StandardError
        nil
      end
      raise
    end

    # 대상 테이블 백업 — 이 파일을 대상 DB 에서 그대로 실행하면 이관 전으로 되돌아감
    def backup_table(t, name, ddl, file)
      n = 0
      Zlib::GzipWriter.open(file.to_s) do |gz|
        gz.write("-- #{name} 이관 전 백업 (#{Time.current.in_time_zone('Asia/Seoul').strftime('%F %T')})\n")
        gz.write("SET NAMES utf8mb4;\nSET time_zone = '+00:00';\nSET FOREIGN_KEY_CHECKS = 0;\n")
        gz.write("DROP TABLE IF EXISTS #{q(name)};\n#{ddl};\n")
        # 생성 칼럼(GENERATED)은 값을 넣을 수 없으므로 빼고 칼럼 이름을 적어 INSERT
        list = column_names(t, name).map { |c| q(c) }.join(', ')
        buf = []
        bytes = 0
        t.query("SELECT #{list} FROM #{q(name)}", stream: true, cache_rows: false, cast: false, as: :array).each do |row|
          v = "(#{row.map { |x| lit(t, x) }.join(',')})"
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
      end
      n
    end

    def save(mig, results, force: false)
      now = Time.now
      return if !force && @last_save && now - @last_save < 3
      @last_save = now
      DbMigration.where(id: mig.id).update_all(results: results.to_json, updated_at: Time.current)
    end

    # 화면 캐시(10분) 지우기 — DbSchemasController#snapshot 과 같은 키
    def clear_cache(link)
      server = DbServer.find_by(id: link.db_server_id)
      return unless server
      Rails.cache.delete(['db_manage', 'snapshot', link.id, server.id, server.updated_at.to_i, link.schema].join('/'))
    end

    # 백업은 프로젝트마다 최근 KEEP_BACKUPS 번 이관분만
    def prune(project_id)
      DbMigration.where(project_id: project_id, backup_removed: false).order(id: :desc).offset(KEEP_BACKUPS).each do |m|
        FileUtils.rm_rf(backup_root.join(project_id.to_s, m.id.to_s))
        m.update_columns(backup_removed: true)
      end
    rescue StandardError
      nil
    end
  end
end
