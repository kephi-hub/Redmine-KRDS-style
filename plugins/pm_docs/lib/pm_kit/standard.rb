# 공공 SI 표준 산출물 목록 (단계 · ID · 이름 · 필수 · 자동 생성 종류)
module PmKit
  module Standard
    LIST = [
      ['start', 'S-01', '사업수행계획서', true, nil], ['start', 'S-02', '착수보고서', true, nil], ['start', 'S-03', 'WBS(일정계획)', true, 'wbs'],
      ['analysis', 'A-01', '요구사항 정의서·추적표', true, 'requirements'], ['analysis', 'A-02', '현행 시스템 분석서', false, nil],
      ['analysis', 'A-03', '인터페이스 정의서', true, 'interfaces'], ['analysis', 'A-04', '변경요청 관리대장', true, 'change_requests'],
      ['design', 'D-01', '아키텍처 설계서', true, nil], ['design', 'D-02', '메뉴 구조도', true, 'menu_tree'], ['design', 'D-03', '화면 설계서', true, nil],
      ['design', 'D-04', '시스템 권한 설계서', true, 'sys_roles'], ['design', 'D-05', '테이블 정의서', true, 'table_def'], ['design', 'D-06', 'ERD', true, 'erd'],
      ['design', 'D-07', '공통코드 정의서', true, 'common_code'], ['design', 'D-08', '용어사전', false, 'glossary'], ['design', 'D-09', '개인정보 처리 설계서', true, 'privacy'],
      ['design', 'D-10', '프로그램 목록', true, 'programs'], ['design', 'D-11', '배치 정의서', false, 'schedules'], ['design', 'D-12', '테스트 계획서·시나리오', true, 'test_cases'],
      ['build', 'B-01', '소스코드', true, 'source'], ['build', 'B-02', '단위 테스트 결과서', true, 'unit_tests'],
      ['test', 'T-01', '통합 테스트 결과서', true, 'integration_tests'], ['test', 'T-02', '인수 테스트 결과서', true, 'acceptance_tests'], ['test', 'T-03', '결함 조치 내역', false, 'defects'],
      ['transition', 'M-01', '이행 계획서', true, nil], ['transition', 'M-02', '데이터 이관 결과서', false, nil], ['transition', 'M-03', '사용자 매뉴얼', true, nil],
      ['transition', 'M-04', '운영자 매뉴얼', true, nil], ['transition', 'M-05', '인프라 자산 목록', false, 'assets'],
      ['close', 'C-01', '완료 보고서', true, nil], ['close', 'C-02', '교육 결과서', false, nil], ['close', 'C-03', '이슈·위험 관리대장', true, 'risks'],
      ['close', 'C-04', '회의록 모음', false, 'meetings'], ['close', 'C-05', '월간 운영 보고서', false, 'monthly_report']
    ].freeze

    module_function

    # 이미 있는 이름은 건너뜀(자동 생성이 비어 있으면 표준 연결만 채움). 반환: 새로 만든 수
    def seed(project)
      existing = PmDeliverable.where(project_id: project.id).index_by(&:name)
      n = 0
      LIST.each_with_index do |(phase, code, name, req, auto), i|
        if (d = existing[name])
          d.update_column(:auto_kind, auto) if auto && d.auto_kind.blank?
          next
        end
        PmDeliverable.create!(project: project, phase: phase, code: code, name: name, required: req, auto_kind: auto, position: i + 1)
        n += 1
      end
      n
    end
  end
end
