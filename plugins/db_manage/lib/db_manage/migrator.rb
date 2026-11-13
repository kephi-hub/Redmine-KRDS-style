# DB 이관 — 원본 DB 의 테이블 구조·데이터를 같은 종류의 대상 DB 로 (MariaDB·MySQL · PostgreSQL · MS SQL Server · Oracle)
# 공통 진행(미리보기·실행·순서·백업 파일·진행 기록·정리)은 여기서, DB 종류별 구조 읽기·DDL·데이터 복사·백업은 Migrate* 엔진
#   엔진(인스턴스 = 연결 하나): prepare · describe(테이블) → 모델|nil · plan(이름, 원본 모델, 대상 모델) · parents(모델)
#                             row_estimates · backup(이름, 모델, gz) · copy_from(원본 엔진, 이름, 방식, 원본 모델, 대상 모델) { |행 수| } · count
# - 구조: 대상에 없으면 만들고, 있으면 칼럼 추가·변경, 인덱스·제약·설명을 원본에 맞춤. 대상에만 있는 것은 지우지 않음, 기본키가 다르면 경고만
# - 데이터: replace(대상 비우고 원본 전체) · upsert(PK·UK 기준 추가·갱신) · insert_new(없는 행만) — 테이블마다 트랜잭션
# - 실행 전 바뀔 대상 테이블을 PMS 서버에 백업 (files/db_migrate/<프로젝트>/<이관 id>/<테이블>.sql.gz — 그 DB 의 클라이언트로 실행하면 복원)
require 'zlib'
require 'fileutils'

module DbManage
  module Migrator
    module_function

    MODES = %w(skip structure replace upsert insert_new).freeze
    # 뷰·함수·프로시저 등 — 이 순서로 만들고, 다른 개체에 기대 실패한 것은 몇 번 더 시도
    OBJ_KINDS = %w(function package view matview procedure).freeze
    OBJ_PASSES = 3
    DATA_MODES = %w(replace upsert insert_new).freeze
    BIG_ROWS = 1_000_000
    KEEP_BACKUPS = 20
    ENGINES = { 'mariadb' => 'MigrateMysql', 'postgresql' => 'MigratePostgresql', 'mssql' => 'MigrateMssql', 'oracle' => 'MigrateOracle' }.freeze
    # 복원 방법 (결과 화면 안내)
    RESTORE = {
      'mariadb' => 'gunzip -c 파일.sql.gz | mysql -h 주소 -u 계정 -p DB이름',
      'postgresql' => 'gunzip -c 파일.sql.gz | psql -h 주소 -U 계정 -d DB이름 -v ON_ERROR_STOP=1',
      'mssql' => 'gunzip -c 파일.sql.gz > 파일.sql && sqlcmd -S 주소 -U 계정 -d DB이름 -i 파일.sql',
      'oracle' => 'gunzip -c 파일.sql.gz > 파일.sql && sql 계정@//주소:포트/서비스 @파일.sql  (SQLcl·SQL*Plus)'
    }.freeze

    def engine_class(adapter)
      DbManage.const_get(ENGINES.fetch(adapter))
    end

    def backup_root
      Pathname.new(Redmine::Configuration['attachments_storage_path'].presence || Rails.root.join('files').to_s).join('db_migrate')
    end

    # 같은 종류의 DB 끼리만
    def supported?(source, target)
      a = source&.db_server&.adapter
      a && ENGINES.key?(a) && a == target&.db_server&.adapter && source.id != target.id
    end

    # 두 연결을 열어 블록에 (원본 엔진, 대상 엔진)
    def open_pair(source, target, write:)
      source.connector.session do |s, _|
        src = engine_class(source.db_server.adapter).new(s, source.schema)
        src.prepare
        target.connector.session(write: write) do |t, _|
          tgt = engine_class(target.db_server.adapter).new(t, target.schema, write: write)
          tgt.prepare
          yield src, tgt
        end
      end
    end

    # 외래키 순서 — 고른 테이블 안에서 참조되는 테이블 먼저 (순환은 원래 순서)
    def ordered(choices, models)
      names = choices.map { |c| c['table'] }
      done = []
      visit = lambda do |n, path|
        return if done.include?(n) || path.include?(n)
        (models[n] ? models[n][:parents] : []).each { |p| visit.call(p, path + [n]) if names.include?(p) && p != n }
        done << n
      end
      names.each { |n| visit.call(n, []) }
      done.map { |n| choices.find { |c| c['table'] == n } }
    end

    # 미리보기 — 고른 테이블마다 계획 (대상은 읽기 연결로 확인)
    # choices: [{ 'table' =>, 'mode' => }] → [{ table:, mode:, status:, statements:, warnings:, rows:, error: }]
    def preview(source, target, choices, objects = [])
      out = []
      open_pair(source, target, write: false) do |src, tgt|
        sort_objects(objects).each do |o|
          item = { object: o['object'], table: o['table'], mode: 'object', statements: [], warnings: [] }
          begin
            item[:statements] = src.object_ddl(o['object'], o['table'], tgt.schema)
            item[:status] = tgt.object_exists?(o['object'], o['table']) ? 'replace' : 'new'
          rescue StandardError => e
            item[:error] = msg(e)
          end
          out << item
        end
        rows = src.row_estimates
        choices.each do |c|
          item = { table: c['table'], mode: c['mode'], rows: rows[c['table']], statements: [], warnings: [] }
          begin
            sm = src.describe(c['table']) or raise Error, I18n.t(:error_db_mig_no_source)
            plan = tgt.plan(c['table'], sm, tgt.describe(c['table']))
            item.merge!(plan.slice(:status, :statements, :warnings))
            item[:error] = I18n.t(:error_db_mig_no_unique) if c['mode'] == 'upsert' && !plan[:unique]
            item[:warnings] += [I18n.t(:text_db_mig_big, rows: item[:rows])] if DATA_MODES.include?(c['mode']) && item[:rows].to_i >= BIG_ROWS
          rescue StandardError => e
            item[:error] = msg(e)
          end
          out << item
        end
        @notes = tgt.respond_to?(:notes) && choices.any? ? tgt.notes : []
      end
      out = out.partition { |x| x[:object].nil? }.flatten
      out.first[:notes] = @notes if out.any?
      out
    end

    def sort_objects(list)
      list.sort_by.with_index { |o, i| [OBJ_KINDS.index(o['object']) || 99, i] }
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
      open_pair(source, target, write: true) do |src, tgt|
        models = {}
        tables, objects = mig.plan_list.partition { |c| c['object'].nil? }
        tables.each do |c|
          models[c['table']] = src.describe(c['table'])
        rescue StandardError
          nil
        end
        ordered(tables, models).each do |c|
          r = { 'table' => c['table'], 'mode' => c['mode'], 'status' => 'running' }
          results << r
          save(mig, results, force: true)
          t0 = Time.now
          begin
            run_table(src, tgt, c['table'], c['mode'], dir, r) { save(mig, results) }
            r['status'] = 'done'
          rescue StandardError => e
            r['status'] = 'failed'
            r['error'] = msg(e)
          end
          r['seconds'] = (Time.now - t0).round(1)
          save(mig, results, force: true)
        end
        run_objects(src, tgt, sort_objects(objects), dir, results) { save(mig, results, force: true) }
      end
      ok = results.count { |x| x['status'] == 'done' }
      mig.update!(status: ok == results.size ? 'done' : (ok.zero? ? 'failed' : 'partial'), finished_at: Time.current, results: results)
    rescue StandardError => e
      Rails.logger.error("[db_migrate] #{mig.id}: #{e.class} #{e.message}")
      mig.update!(status: 'failed', finished_at: Time.current, results: results, error: msg(e, 1000))
    ensure
      clear_cache(mig.target_link) if mig.target_link
      prune(mig.project_id)
    end

    def run_table(src, tgt, name, mode, dir, r)
      sm = src.describe(name) or raise Error, I18n.t(:error_db_mig_no_source)
      tm = tgt.describe(name)
      plan = tgt.plan(name, sm, tm)
      r['plan'] = plan[:status]
      r['warnings'] = plan[:warnings]
      data = DATA_MODES.include?(mode)
      raise Error, I18n.t(:error_db_mig_no_unique) if mode == 'upsert' && !plan[:unique]
      if tm && (plan[:statements].any? || data)
        FileUtils.mkdir_p(dir)
        file = dir.join("#{name.gsub(/[^\w.-]/, '_')}.sql.gz")
        Zlib::GzipWriter.open(file.to_s) { |gz| r['backup_rows'] = tgt.backup(name, tm, gz) }
        r['backup'] = file.basename.to_s
        r['backup_bytes'] = File.size(file)
        yield
      end
      plan[:statements].each { |sql| tgt.exec(sql) }
      r['ddl'] = plan[:statements]
      return unless data
      tm2 = tgt.describe(name)
      r['rows'] = tgt.copy_from(src, name, mode, sm, tm2) do |n|
        r['rows'] = n
        yield
      end
      r['target_rows'] = tgt.count(name)
    end

    # 뷰·함수·프로시저 — 만들기 전 대상의 지금 정의를 백업, 다른 개체에 기대 실패하면 다음 차례에 다시
    def run_objects(src, tgt, objects, dir, results)
      rows = objects.map do |o|
        r = { 'object' => o['object'], 'table' => o['table'], 'mode' => 'object', 'status' => 'queued' }
        results << r
        r
      end
      yield
      OBJ_PASSES.times do |pass|
        pending = rows.reject { |r| r['status'] == 'done' }
        break if pending.empty?
        progress = false
        pending.each do |r|
          t0 = Time.now
          r['status'] = 'running'
          begin
            ddl = src.object_ddl(r['object'], r['table'], tgt.schema)
            # 이관 전 상태는 첫 시도 전에만 (앞 차례에 실패하며 남은 개체를 백업하지 않게)
            if pass.zero? && (script = tgt.object_script(r['object'], r['table']))
              FileUtils.mkdir_p(dir)
              file = dir.join("#{r['object']}_#{r['table'].gsub(/[^\w.-]/, '_')}.sql.gz")
              Zlib::GzipWriter.open(file.to_s) { |gz| gz.write(script) }
              r['backup'] = file.basename.to_s
              r['backup_bytes'] = File.size(file)
            end
            r['plan'] ||= r['backup'] ? 'replace' : 'new'
            tgt.create_object(r['object'], r['table'], ddl)
            r['ddl'] = ddl
            r['status'] = 'done'
            r.delete('error')
            progress = true
          rescue StandardError => e
            r['status'] = 'failed'
            r['error'] = msg(e)
            r['ddl'] = ddl if ddl
          end
          r['seconds'] = ((r['seconds'] || 0) + (Time.now - t0)).round(1)
          r['passes'] = pass + 1
          yield
        end
        break unless progress
      end
    end

    def msg(error, len = 500)
      error.message.to_s.dup.force_encoding('UTF-8').scrub.strip.truncate(len)
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

  # 엔진 공통
  class MigrateBase
    BATCH_BYTES = 1_000_000

    def initialize(conn, schema, write: false)
      @c = conn
      @schema = schema
      @write = write
    end

    attr_reader :c, :schema

    def prepare; end

    def parents(model)
      model ? model[:parents] : []
    end

    private

    def t(key, **args)
      I18n.t(key, **args)
    end

    # 원본을 끝까지 읽으며 행마다 블록 — 블록에서 오류가 나도 남은 행은 읽고 버린 뒤 오류를 올림 (같은 연결을 다시 쓰기 위해)
    def drain(each_row)
      failure = nil
      each_row.call do |row|
        next if failure
        begin
          yield row
        rescue StandardError => e
          failure = e
        end
      end
      raise failure if failure
    end
  end
end
