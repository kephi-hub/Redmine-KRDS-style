# 프로젝트 > DB — 테이블 목록·컬럼 상세, 테이블 정의서(엑셀), 개발/운영 비교, 용어사전 점검
# 원격 DB 에는 읽기 전용 세션으로 메타데이터만 조회
require 'csv'
class DbSchemasController < ApplicationController
  menu_item :db_schemas
  helper :db_schemas

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :load_links
  before_action :find_link, only: [:table, :object, :export, :check, :erd, :history, :save_history, :history_diff, :query, :query_log, :privacy, :save_privacy]

  def index
    @link = @links.find { |l| l.id.to_s == params[:link].to_s } || @links.first
    return unless @link
    @snapshot = snapshot(@link, objects: true)
    @terms = DbManage::Analysis.term_map(@project)
    @kind = @snapshot && @snapshot[:kinds].include?(params[:kind]) ? params[:kind] : 'table'
  end

  def table
    @snapshot = snapshot(@link, objects: true)
    return unless @snapshot
    @table = @snapshot[:tables].find { |t| t[:name] == params[:table] }
    return render_404 unless @table
    @columns = @snapshot[:columns][@table[:name]] || []
    @terms = DbManage::Analysis.term_map(@project)
    # 뷰·구체화 뷰는 정의(SQL)도, 테이블은 걸린 트리거도 보여 줌
    @view = (@snapshot.dig(:objects, 'view').to_a + @snapshot.dig(:objects, 'matview').to_a).find { |v| v[:name] == @table[:name] } if @table[:view]
    @triggers = @snapshot.dig(:objects, 'trigger').to_a.select { |t| t[:table] == @table[:name] }
    @privacy = DbPrivacyColumn.where(db_link_id: @link.id, table_name: @table[:name]).index_by(&:column_name)
  end

  # 함수·프로시저·트리거·DB 잡·시퀀스 상세 (정의 SQL 포함)
  def object
    @snapshot = snapshot(@link, objects: true)
    return unless @snapshot
    @kind = params[:kind].to_s
    return render_404 unless @snapshot[:kinds].include?(@kind) && !%w(table view matview).include?(@kind)
    @object = @snapshot.dig(:objects, @kind).to_a.find { |o| o[:key] == params[:key] }
    render_404 unless @object
  end

  # 테이블 정의서 — 시트 1: 테이블 목록, 시트 2: 컬럼 정의
  def export
    snap = snapshot(@link, objects: true)
    return redirect_to(project_db_schemas_path(@project, link: @link.id)) unless snap
    terms = DbManage::Analysis.term_map(@project)
    tables = snap[:tables].each_with_index.map do |t, i|
      [i + 1, t[:name], t[:view] ? '뷰' : '테이블', t[:comment], (snap[:columns][t[:name]] || []).size, t[:view] ? nil : t[:rows]]
    end
    columns = []
    snap[:tables].each do |t|
      (snap[:columns][t[:name]] || []).each do |c|
        term = terms && DbManage::Analysis.term_status(c, terms).last
        columns << [t[:name], t[:comment], c[:position], c[:name], c[:type], c[:nullable] ? 'Y' : 'N', c[:default], c[:keys].join(', '), c[:ref], c[:comment], term&.name]
      end
    end
    sheets = [
      { name: '테이블 목록', header: %w(No 테이블명 구분 설명 컬럼\ 수 행\ 수(추정)), rows: tables, widths: [6, 30, 8, 40, 10, 14] },
      { name: '컬럼 정의', header: %w(테이블명 테이블\ 설명 No 컬럼명 데이터\ 타입 Null 기본값 키 참조 설명 용어), rows: columns,
        widths: [26, 24, 6, 26, 20, 6, 18, 10, 24, 36, 18] }
    ]
    idx_rows = []
    snap[:tables].each do |t|
      (snap[:indexes].to_h[t[:name]] || []).each do |i|
        idx_rows << [t[:name], i[:name], i[:primary] ? 'PK' : (i[:unique] ? 'UNIQUE' : 'INDEX'), i[:columns].join(', '), i[:method]]
      end
    end
    sheets << { name: '인덱스', header: %w(테이블명 인덱스명 구분 컬럼(순서) 방식), rows: idx_rows, widths: [26, 30, 10, 50, 10] } if idx_rows.any?
    # 시트 3: 뷰 정의·함수·프로시저·트리거·DB 잡·시퀀스 (엑셀 칸 최대 글자 수 때문에 정의는 3만 자까지)
    objects = []
    (snap[:kinds] - ['table']).each do |kind|
      snap.dig(:objects, kind).to_a.each do |o|
        detail = o[:args] || o[:table] || o[:schedule] || (o[:start] && "#{o[:start]} 부터 #{o[:increment]}씩")
        extra = o[:returns] || o[:timing] || o[:type]
        objects << [l("label_db_kind_#{kind}"), o[:name], detail, extra, o[:status], o[:comment], o[:definition].to_s[0, 30_000]]
      end
    end
    if objects.any?
      sheets << { name: '뷰·함수·트리거·잡', header: %w(종류 이름 인자·대상·일정 반환·시점·타입 상태 설명 정의), rows: objects,
                  widths: [12, 28, 30, 22, 10, 30, 60] }
    end
    name = "테이블정의서_#{@project.identifier}_#{@link.name}_#{User.current.today.strftime('%Y%m%d')}.xlsx"
    send_data KrdsUi::Xlsx.build(sheets), filename: name,
              type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  end

  # ERD (Mermaid) — 화면 보기, download=md|mmd 내려받기 (SVG·PNG 는 화면에서 그림을 그대로 저장)
  def erd
    @snapshot = snapshot(@link)
    return unless @snapshot
    all = @snapshot[:tables].map { |t| t[:name] }
    picked = Array(params[:t]).map(&:to_s) & all
    @picked = picked.any? ? picked : nil
    @columns = %w(all keys none).include?(params[:cols]) ? params[:cols] : 'all'
    @inferred = params.key?(:applied) ? params[:inferred] == '1' : true
    @erd = DbManage::Erd.build(@snapshot, tables: @picked, columns: @columns, inferred: @inferred)
    base = "ERD_#{@project.identifier}_#{@link.name}_#{User.current.today.strftime('%Y%m%d')}"
    case params[:download]
    when 'mmd'
      send_data @erd[:mermaid], filename: "#{base}.mmd", type: 'text/plain; charset=utf-8'
    when 'drawio'
      send_data DbManage::Erd.drawio(@erd, "#{@project.name} #{@link.name} ERD"), filename: "#{base}.drawio", type: 'application/xml; charset=utf-8'
    when 'md'
      info = "- DB: #{helpers.db_link_info(@link)}
- 생성: #{format_time(Time.now)} · 테이블 #{@erd[:tables].size} · 관계 #{@erd[:relations].size}"
      send_data DbManage::Erd.markdown("#{@project.name} · #{@link.name} ERD", info, @erd), filename: "#{base}.md", type: 'text/markdown; charset=utf-8'
    end
  end

  # SQL 조회 — 조회 문장 하나, 읽기 전용 트랜잭션·시간·건수 제한, 모든 실행(거부 포함) 기록
  QUERY_LIMITS = [100, 500, 1000].freeze

  def query
    perm = @link.production? ? :run_db_query_production : :run_db_query
    return deny_access unless User.current.allowed_to?(perm, @project)
    @limit = QUERY_LIMITS.include?(params[:limit].to_i) ? params[:limit].to_i : QUERY_LIMITS.first
    @recent = DbQueryLog.where(db_link_id: @link.id, user_id: User.current.id).recent.limit(10).to_a
    return unless request.post?
    @sql = params[:sql].to_s
    clean, reason = DbManage::SqlGuard.check(@sql)
    if reason
      log_query('blocked', message: reason)
      return @error = reason
    end
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    begin
      @result = @link.connector.select(clean, limit: @limit, seconds: [@link.db_server.timeout * 3, 60].min)
    rescue DbManage::Error => e
      log_query('error', message: e.message, ms: elapsed(t0))
      return @error = e.message
    end
    @ms = elapsed(t0)
    log_query('ok', rows: @result[:rows].size, ms: @ms)
    return unless params[:csv] == '1'
    data = CSV.generate do |csv|
      csv << @result[:columns]
      @result[:rows].each { |r| csv << r }
    end
    send_data "\uFEFF" + data, type: 'text/csv; charset=utf-8',
              filename: "SQL_#{@project.identifier}_#{@link.name}_#{User.current.today.strftime('%Y%m%d')}.csv"
  end

  # SQL 조회 실행 기록 (DB 연결 관리 권한)
  def query_log
    @logs = DbQueryLog.where(db_link_id: @link.id).recent.includes(:user).limit(300).to_a
  end

  # 구조 변경 이력: 저장본 목록 (바로 앞 저장본과의 차이 요약)
  def history
    @snapshots = @link.db_snapshots.recent.includes(:user).limit(DbSnapshot::KEEP).to_a
  end

  # 지금 구조 저장 (바뀌었을 때만)
  def save_history
    state, rec = DbSnapshot.capture(@link, User.current)
    flash[:notice] = state == :saved ? l(:notice_db_snapshot_saved, tables: rec.table_count) : l(:notice_db_snapshot_same)
  rescue DbManage::Error => e
    flash[:error] = e.message
  ensure
    redirect_to project_db_history_path(@project, @link) unless performed?
  end

  # 저장본 비교: 기본은 바로 앞 저장본 → 이 저장본, base=current 면 이 저장본 → 지금 DB
  def history_diff
    @snap = @link.db_snapshots.find_by(id: params[:id])
    return render_404 unless @snap
    if params[:base] == 'current'
      cur = snapshot(@link)
      return unless cur
      @older, @newer = @snap.structure, cur
      @name_a, @name_b = l(:label_db_history_this), l(:label_db_history_now)
      @time_a, @time_b = @snap.created_at, nil
    else
      base = params[:base].present? ? @link.db_snapshots.find_by(id: params[:base]) : @link.db_snapshots.where('created_at < ? OR (created_at = ? AND id < ?)', @snap.created_at, @snap.created_at, @snap.id).recent.first
      return @first = true unless base
      @base = base
      @older, @newer = base.structure, @snap.structure
      @name_a, @name_b = l(:label_db_history_prev), l(:label_db_history_this)
      @time_a, @time_b = base.created_at, @snap.created_at
    end
    @result = DbManage::Analysis.compare(@older, @newer)
    @objects = DbManage::Analysis.compare_objects(@older, @newer, @link.schema, @link.schema)
  end

  # 두 DB(기본: 운영 아님 ↔ 운영) 의 테이블·컬럼 차이
  def compare
    return if @links.size < 2
    @a = @links.find { |l| l.id.to_s == params[:a].to_s } || @links.find { |l| !l.production? } || @links.first
    @b = @links.find { |l| l.id.to_s == params[:b].to_s } || (@links - [@a]).find(&:production?) || (@links - [@a]).first
    return if @a == @b
    sa = snapshot(@a, objects: true); sb = sa && snapshot(@b, objects: true)
    return unless sa && sb
    @result = DbManage::Analysis.compare(sa, sb)
    @objects = DbManage::Analysis.compare_objects(sa, sb, @a.schema, @b.schema)
  end

  # 컬럼명(중복 제거)을 용어사전 약어와 대조. format=csv 는 미등록 컬럼을 용어사전 가져오기 양식으로
  def check
    @terms = DbManage::Analysis.term_map(@project)
    return unless @terms
    snap = snapshot(@link)
    return unless snap
    rows = {}
    snap[:tables].each do |t|
      (snap[:columns][t[:name]] || []).each do |c|
        r = rows[c[:name].upcase] ||= { name: c[:name], tables: [], comments: [], types: [], column: c }
        r[:tables] << t[:name]
        r[:comments] |= [c[:comment]].compact
        r[:types] |= [c[:type]]
      end
    end
    rows.each_value { |r| r[:status], r[:term] = DbManage::Analysis.term_status(r[:column], @terms) }
    @rows = rows.values.sort_by { |r| [%i(type missing ok).index(r[:status]), r[:name]] }
    @counts = @rows.group_by { |r| r[:status] }.transform_values(&:size)
    @status = %w(ok type missing).include?(params[:status]) ? params[:status].to_sym : nil
    if params[:format] == 'csv'
      data = CSV.generate do |csv|
        csv << %w(용어 영문명 약어 분류 데이터타입 길이 정의 비고)
        @rows.select { |r| r[:status] == :missing }.each do |r|
          base, len = DbManage::Analysis.split_type(r[:types].first)
          csv << [r[:comments].first.presence || r[:name], nil, r[:name].upcase, nil, base.upcase, len.presence, nil, "사용 테이블: #{r[:tables].first(5).join(', ')}"]
        end
      end
      return send_data("﻿" + data, type: 'text/csv; charset=utf-8',
                       filename: "미등록컬럼_#{@project.identifier}_#{@link.name}_#{User.current.today.strftime('%Y%m%d')}.csv")
    end
    @shown = @status ? @rows.select { |r| r[:status] == @status } : @rows
    @tab = %w(name comment mismatch).include?(params[:tab]) ? params[:tab] : 'name'
    # 설명(코멘트)이 없는 테이블·컬럼
    @no_comment_tables = snap[:tables].reject { |t| t[:view] || t[:comment].present? }
    @no_comment_columns = snap[:tables].reject { |t| t[:view] }.flat_map do |t|
      (snap[:columns][t[:name]] || []).select { |c| c[:comment].blank? }.map { |c| [t[:name], c] }
    end
    # 용어사전에 있는 컬럼인데 설명이 용어 이름과 다른 것
    @mismatch = snap[:tables].reject { |t| t[:view] }.flat_map do |t|
      (snap[:columns][t[:name]] || []).filter_map do |c|
        term = @terms[c[:name].to_s.upcase]
        next unless term && c[:comment].present?
        a = c[:comment].to_s.gsub(/\s+/, ''); b = term.name.to_s.gsub(/\s+/, '')
        [t[:name], c, term] unless a == b || a.start_with?(b)
      end
    end
  end

  # 개인정보 컬럼: 확정 목록 · 자동 후보 · 경고, 엑셀(download=xlsx)
  def privacy
    snap = snapshot(@link)
    @terms = DbManage::Analysis.term_map(@project)
    records = DbPrivacyColumn.where(db_link_id: @link.id).includes(:user).to_a
    cols = {}
    snap&.dig(:tables)&.reject { |t| t[:view] }&.each do |t|
      (snap[:columns][t[:name]] || []).each { |c| cols["#{t[:name]}.#{c[:name]}"] = [t, c] }
    end
    order = DbPrivacyColumn::CATEGORIES
    @rows = records.map do |r|
      t, c = cols[r.key]
      { rec: r, table: r.table_name, column: r.column_name, col: c, table_comment: t&.dig(:comment), gone: snap && c.nil?, judge: r.judge }
    end.sort_by { |x| [order.index(x[:rec].category), x[:table], x[:column]] }
    @candidates = snap ? DbManage::Privacy.candidates(snap, @terms, records.map(&:key).to_set) : []
    @candidates.sort_by! { |x| [order.index(x[:category]), x[:table], x[:column]] }
    personal = @rows.select { |x| x[:rec].personal? }
    @kpi = { personal: personal.size, required: personal.count { |x| DbPrivacyColumn::REQUIRED.include?(x[:rec].category) },
             warn: personal.count { |x| x[:judge] == :warn }, check: personal.count { |x| x[:judge] == :check },
             candidates: @candidates.size, gone: @rows.count { |x| x[:gone] } }
    return privacy_xlsx(personal) if params[:download] == 'xlsx'
    tabs = %w(list candidates warn none)
    @tab = tabs.include?(params[:tab]) ? params[:tab] : (records.empty? && @candidates.any? ? 'candidates' : 'list')
    @none_count = @rows.count { |x| !x[:rec].personal? }
    @shown = case @tab
             when 'list' then personal
             when 'warn' then @rows.select { |x| x[:gone] || %i(warn check).include?(x[:judge]) }
             when 'none' then @rows.reject { |x| x[:rec].personal? }
             else []
             end
    @can_edit = User.current.allowed_to?({ controller: 'db_schemas', action: 'save_privacy' }, @project)
  end

  # 개인정보 컬럼 저장: rows[n][t|c|category|encryption|note|cand|on] — 후보 줄은 고른 것(on)만, 분류를 비우면 삭제
  def save_privacy
    input = params[:rows].respond_to?(:to_unsafe_h) ? params[:rows].to_unsafe_h.values : []
    existing = DbPrivacyColumn.where(db_link_id: @link.id).index_by(&:key)
    # 지금 DB 에 있는 컬럼(또는 이미 저장된 컬럼)만 저장
    snap = snapshot(@link)
    allowed = existing.keys.to_set
    snap&.dig(:tables)&.reject { |t| t[:view] }&.each { |t| (snap[:columns][t[:name]] || []).each { |c| allowed << "#{t[:name]}.#{c[:name]}" } }
    changed = 0
    DbPrivacyColumn.transaction do
      input.each do |row|
        next unless row.respond_to?(:[])
        t = row['t'].to_s; c = row['c'].to_s
        next if t.blank? || c.blank?
        next if row['cand'] == '1' && row['on'] != '1'
        next unless allowed.include?("#{t}.#{c}")
        rec = existing["#{t}.#{c}"]
        cat = row['category'].to_s.presence_in(DbPrivacyColumn::CATEGORIES)
        if cat.nil?
          if rec
            rec.destroy
            changed += 1
          end
          next
        end
        rec ||= DbPrivacyColumn.new(db_link_id: @link.id, table_name: t.truncate(128, omission: ''), column_name: c.truncate(128, omission: ''))
        rec.assign_attributes(category: cat, encryption: row['encryption'].to_s.presence_in(DbPrivacyColumn::ENCRYPTIONS) || 'unknown',
                              note: row['note'].to_s.strip.truncate(255).presence)
        next unless rec.changed?
        rec.user_id = User.current.id
        rec.save!
        changed += 1
      end
    end
    flash[:notice] = l(:notice_db_privacy_saved, count: changed)
    redirect_to project_db_privacy_path(@project, @link, tab: params[:tab].presence)
  end

  private

  def privacy_xlsx(personal)
    lb = ->(k, v) { l("label_db_pv_#{k}_#{v}") }
    rows = personal.map do |x|
      r = x[:rec]; c = x[:col] || {}
      judge = x[:gone] ? l(:label_db_pv_gone) : l("label_db_pv_judge_#{x[:judge]}")
      [r.table_name, x[:table_comment], r.column_name, c[:type], c[:comment], lb.('cat', r.category), lb.('enc', r.encryption), judge, r.note, r.user&.name,
       r.updated_at && format_time(r.updated_at)]
    end
    summary = DbPrivacyColumn::CATEGORIES.reject { |k| k == 'none' }.map do |k|
      list = personal.select { |x| x[:rec].category == k }
      [lb.('cat', k), list.size, list.count { |x| x[:judge] == :warn }, list.count { |x| x[:judge] == :check }]
    end
    data = KrdsUi::Xlsx.build([
      { name: '개인정보 컬럼', header: %w(테이블명 테이블\ 설명 컬럼명 데이터\ 타입 컬럼\ 설명 분류 암호화 판정 비고 확인자 확인일시), rows: rows,
        widths: [26, 24, 24, 18, 30, 16, 12, 14, 30, 12, 18] },
      { name: '분류별 요약', header: %w(분류 컬럼\ 수 경고 확인\ 필요), rows: summary, widths: [18, 10, 10, 10] }
    ])
    send_data data, filename: "개인정보컬럼_#{@project.identifier}_#{@link.name}_#{User.current.today.strftime('%Y%m%d')}.xlsx",
                    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  end

  def log_query(status, rows: nil, ms: nil, message: nil)
    DbQueryLog.create!(db_link_id: @link.id, user_id: User.current.id, sql: @sql.to_s.truncate(20_000), status: status,
                       row_count: rows, duration_ms: ms, message: message.to_s.truncate(250).presence, created_at: Time.now)
  end

  def elapsed(t0)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round
  end

  def load_links
    @links = @project.db_links.includes(:db_server).sorted.to_a
  end

  def find_link
    @link = @links.find { |l| l.id.to_s == params[:link_id].to_s }
    render_404 unless @link
  end

  # 접속 실패는 화면에 메시지로 보여 주고 nil
  # 화면마다 DB 에 새로 접속하지 않게 10분 동안 보관 (객체 정의까지 한 번에). refresh=1 이면 새로 읽음
  CACHE_TTL = 10.minutes

  def snapshot(link, objects: false)
    key = ['db_manage', 'snapshot', link.id, link.db_server.id, link.db_server.updated_at.to_i, link.schema].join('/')
    Rails.cache.delete(key) if params[:refresh] == '1' && !@refreshed&.include?(link.id)
    (@refreshed ||= []) << link.id
    Rails.cache.fetch(key, expires_in: CACHE_TTL) { link.connector.snapshot(objects: true) }
  rescue DbManage::Error => e
    @db_error = "#{link.name}: #{e.message}"
    nil
  end
end
