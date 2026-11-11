# 행정안전부 "공공데이터 공통표준용어" CSV(공공데이터포털 배포 형식)를 용어사전 칸으로 바꿈
# 머리줄: 공통표준용어명, 공통표준용어설명, 공통표준용어영문약어명, 공통표준도메인명, 허용값, 저장 형식, 표현 형식,
#        행정표준코드명, 소관기관명, 용어 이음동의어 목록, 제정차수, 개정구분명(폐기 또는 변경), 개정항목, 개정사유
module Glossary
  module Mois
    NAME = '공통표준용어명'
    TYPES = { 'V' => 'VARCHAR', 'C' => 'CHAR', 'N' => 'NUMERIC', 'D' => 'DATETIME' }.freeze
    # 비고에 모아 적는 칸 (도메인명은 맨 앞)
    NOTES = [%w(허용값 허용값), ['저장 형식', '저장 형식'], ['표현 형식', '표현 형식'], %w(행정표준코드 행정표준코드명),
             %w(소관기관 소관기관명), ['이음동의어', '용어 이음동의어 목록'], %w(제정 제정차수), ['개정', '개정구분명(폐기 또는 변경)']].freeze

    module_function

    def match?(headers)
      headers.compact.map { |h| h.to_s.strip }.include?(NAME)
    end

    # 폐기된 판(개정구분 "폐기" 또는 제정차수 "(폐기)" — "폐기후제정"은 새 판이라 포함)은 뺌
    # 반환: [용어 속성 배열, 뺀 건수]
    def rows(table)
      dropped = 0
      list = table.filter_map do |row|
        g = ->(k) { row[k].to_s.strip }
        if g.('개정구분명(폐기 또는 변경)') == '폐기' || g.('제정차수').match?(/\(폐기\)/)
          dropped += 1
          next
        end
        domain = g.('공통표준도메인명')
        m = domain.match(/\A(.*?)([VCND])([\d,]*)\z/)
        notes = (domain.present? ? ["도메인: #{domain}"] : []) + NOTES.filter_map { |label, k| (v = g.(k)).present? ? "#{label}: #{v}" : nil }
        { 'name' => g.(NAME), 'abbr' => g.('공통표준용어영문약어명'), 'category' => m ? m[1] : domain,
          'data_type' => m && TYPES[m[2]], 'data_length' => m && m[3], 'definition' => g.('공통표준용어설명'), 'note' => notes.join(' · ') }
      end
      [list, dropped]
    end
  end
end
