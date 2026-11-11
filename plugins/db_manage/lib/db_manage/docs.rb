# DB 산출물 엑셀 — 테이블 정의서, 개인정보 컬럼, 공통코드 정의서 (DB 화면과 산출물 일괄 패키지가 같이 씀)
module DbManage
  module Docs
    module_function

    def fmt(t)
      t && t.in_time_zone(ActiveSupport::TimeZone['Asia/Seoul']).strftime('%Y-%m-%d %H:%M')
    end

    # 테이블 정의서: 테이블 목록 · 컬럼 정의 · 인덱스 · 뷰·함수·트리거·잡
    def table_definition(snap, terms)
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
          objects << [I18n.t("label_db_kind_#{kind}"), o[:name], detail, extra, o[:status], o[:comment], o[:definition].to_s[0, 30_000]]
        end
      end
      if objects.any?
        sheets << { name: '뷰·함수·트리거·잡', header: %w(종류 이름 인자·대상·일정 반환·시점·타입 상태 설명 정의), rows: objects,
                    widths: [12, 28, 30, 22, 10, 30, 60] }
      end
      KrdsUi::Xlsx.build(sheets)
    end

    # 개인정보 컬럼: personal = DbManage::Privacy.rows 중 개인정보인 것
    def privacy(personal)
      lb = ->(k, v) { I18n.t("label_db_pv_#{k}_#{v}") }
      rows = personal.map do |x|
        r = x[:rec]; c = x[:col] || {}
        judge = x[:gone] ? I18n.t(:label_db_pv_gone) : I18n.t("label_db_pv_judge_#{x[:judge]}")
        [r.table_name, x[:table_comment], r.column_name, c[:type], c[:comment], lb.('cat', r.category), lb.('enc', r.encryption), judge, r.note, r.user&.name, fmt(r.updated_at)]
      end
      summary = DbPrivacyColumn::CATEGORIES.reject { |k| k == 'none' }.map do |k|
        list = personal.select { |x| x[:rec].category == k }
        [lb.('cat', k), list.size, list.count { |x| x[:judge] == :warn }, list.count { |x| x[:judge] == :check }]
      end
      KrdsUi::Xlsx.build([
        { name: '개인정보 컬럼', header: %w(테이블명 테이블\ 설명 컬럼명 데이터\ 타입 컬럼\ 설명 분류 암호화 판정 비고 확인자 확인일시), rows: rows,
          widths: [26, 24, 24, 18, 30, 16, 12, 14, 30, 12, 18] },
        { name: '분류별 요약', header: %w(분류 컬럼\ 수 경고 확인\ 필요), rows: summary, widths: [18, 10, 10, 10] }
      ])
    end
  end
end
