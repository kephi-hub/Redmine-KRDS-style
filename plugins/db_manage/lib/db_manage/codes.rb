# 공통코드 정의서 — 지정한 코드 테이블을 읽기 전용으로 읽어 그룹별 코드 목록·엑셀
# - 테이블·컬럼 이름은 지금 DB 스냅샷에 있는 것만 허용하고 DB 종류에 맞게 따옴표 처리 (SQL 을 사용자에게서 받지 않음)
# - SQL 조회와 같은 안전장치(SqlGuard, 읽기 전용 트랜잭션, 시간·건수 제한)
module DbManage
  module Codes
    module_function

    KEYS = %w(table group code name group_name order use).freeze
    LIMIT = 5000

    def config(link)
      raw = JSON.parse(link.code_config.to_s) rescue {}
      raw.is_a?(Hash) ? raw.slice(*KEYS) : {}
    end

    def configured?(link)
      c = config(link)
      c['table'].present? && c['group'].present? && c['code'].present? && c['name'].present?
    end

    # 지금 스냅샷 기준으로 검증한 설정 (틀리면 Error)
    def validate(cfg, snap)
      table = snap[:tables].find { |t| t[:name] == cfg['table'] && !t[:view] } || snap[:tables].find { |t| t[:name] == cfg['table'] }
      raise Error, I18n.t(:error_db_code_table) unless table
      cols = (snap[:columns][table[:name]] || []).map { |c| c[:name] }
      KEYS.drop(1).each do |k|
        next if cfg[k].blank?
        raise Error, I18n.t(:error_db_code_column, name: cfg[k]) unless cols.include?(cfg[k])
      end
      %w(group code name).each { |k| raise Error, I18n.t(:error_db_code_required) if cfg[k].blank? }
      cfg
    end

    def quote(adapter, name)
      case adapter
      when 'mariadb' then "`#{name.gsub('`', '``')}`"
      when 'mssql' then "[#{name.gsub(']', ']]')}]"
      else %("#{name.gsub('"', '""')}")
      end
    end

    def sql(link, cfg)
      a = link.db_server.adapter
      q = ->(n) { quote(a, n) }
      cols = %w(group code name group_name order use).map { |k| cfg[k].present? ? q.(cfg[k]) : 'NULL' }
      order = [q.(cfg['group']), (cfg['order'].present? ? q.(cfg['order']) : nil), q.(cfg['code'])].compact.join(', ')
      "SELECT #{cols.join(', ')} FROM #{q.(link.schema)}.#{q.(cfg['table'])} ORDER BY #{order}"
    end

    # { rows: [[그룹, 코드, 코드명, 그룹명, 순서, 사용]], groups: [[그룹, 그룹명, 코드 수]], truncated: }
    def fetch(link, snap)
      cfg = validate(config(link), snap)
      text = sql(link, cfg)
      clean, reason = DbManage::SqlGuard.check(text)
      raise Error, reason if reason
      res = link.connector.select(clean, limit: LIMIT, seconds: [link.db_server.timeout * 3, 60].min)
      rows = res[:rows].map { |r| r.map { |v| v.nil? ? nil : v.to_s } }
      groups = rows.group_by(&:first).map { |g, list| [g, list.map { |r| r[3] }.compact.first, list.size] }
      { rows: rows, groups: groups, truncated: rows.size >= LIMIT, config: cfg }
    end

    def xlsx(result)
      KrdsUi::Xlsx.build([
        { name: '코드 그룹', header: %w(그룹\ 코드 그룹명 코드\ 수), rows: result[:groups], widths: [20, 30, 10] },
        { name: '코드 값', header: %w(그룹\ 코드 코드 코드명 그룹명 순서 사용), rows: result[:rows].map { |g, c, n, gn, o, u| [g, c, n, gn, o, u] },
          widths: [20, 16, 30, 24, 8, 8] }
      ])
    end
  end
end
