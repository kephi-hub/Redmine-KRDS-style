# 엑셀 내보내기 — 자산 대장 · 배치 정의서 · 인터페이스 정의서
module OpsKit
  module Sheet
    module_function

    XLSX = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'.freeze
    LABEL = {
      'kind' => { 'server' => '서버', 'domain' => '도메인', 'cert' => 'SSL 인증서', 'license' => '라이선스', 'cloud' => '클라우드', 'device' => '장비' },
      'env' => { 'prod' => '운영', 'dev' => '개발', 'test' => '테스트', 'common' => '공통' },
      'skind' => { 'cron' => 'cron', 'spring' => 'Spring @Scheduled', 'quartz' => 'Quartz', 'windows' => 'Windows 작업 스케줄러', 'jenkins' => 'Jenkins',
                   'db_job' => 'DB 잡', 'other' => '기타' },
      'direction' => { 'send' => '송신', 'recv' => '수신', 'both' => '양방향' },
      'protocol' => { 'rest' => 'REST', 'soap' => 'SOAP', 'db_link' => 'DB 링크', 'sftp' => '파일(SFTP)', 'mq' => 'MQ', 'batch' => '배치', 'other' => '기타' },
      'cycle' => { 'realtime' => '실시간', 'schedule' => '스케줄', 'manual' => '수동' },
      'istatus' => { 'active' => '운영', 'dev' => '개발 중', 'stopped' => '중지' },
      'status' => { 'open' => '처리 중', 'closed' => '종료' },
      'check' => { 'ok' => '정상', 'issue' => '이상', 'na' => '해당 없음' }
    }.freeze

    def assets(list, project = nil)
      rows = list.map do |a|
        [LABEL['kind'][a.kind], a.name, LABEL['env'][a.env], a.address, a.spec, a.vendor, a.owner, a.expires_on&.to_s, a.days_left, a.renew_cycle,
         a.shared? ? '공용' : a.project&.name, a.active? ? 'Y' : 'N', a.note]
      end
      KrdsUi::Xlsx.build([{ name: '자산 대장', header: %w(종류 이름 구분 주소 사양 공급사 담당 만료일 남은\ 일 갱신\ 주기 소속 사용 비고), rows: rows,
                            widths: [10, 26, 6, 30, 30, 16, 12, 12, 8, 10, 16, 6, 30] }])
    end

    def schedules(list)
      rows = list.map do |s|
        nxt = s.next_runs(1).first
        [s.name, LABEL['skind'][s.kind], s.ops_asset&.name, s.expression, s.describe, nxt && OpsKit::Report.fmt(nxt), s.command, s.run_as, s.duration_min,
         s.depends_on, s.on_failure, s.owner, s.related, s.active? ? 'Y' : 'N', s.note]
      end
      KrdsUi::Xlsx.build([{ name: '배치 정의서', header: %w(작업명 종류 실행\ 서버 일정 일정\ 풀이 다음\ 실행 명령·클래스 실행\ 계정 소요(분) 선행·후행 실패\ 시\ 대응 담당 관련 사용 비고),
                            rows: rows, widths: [24, 12, 16, 18, 22, 17, 40, 10, 8, 24, 30, 10, 24, 6, 24] }])
    end

    def interfaces(list)
      rows = list.map do |i|
        [i.code, i.name, LABEL['direction'][i.direction], i.partner, LABEL['protocol'][i.protocol], LABEL['cycle'][i.cycle], i.ops_schedule&.describe,
         i.data_desc, i.tables, i.dev_url, i.prod_url, i.our_owner, i.partner_owner, i.partner_contact, i.auth_note, LABEL['istatus'][i.status], i.note]
      end
      KrdsUi::Xlsx.build([{ name: '인터페이스 정의서', header: %w(ID 인터페이스명 방향 상대\ 시스템 방식 주기 일정 주고받는\ 데이터 관련\ 테이블 개발\ 주소 운영\ 주소 우리\ 담당 상대\ 담당 상대\ 연락처 인증 상태 비고),
                            rows: rows, widths: [10, 26, 8, 20, 10, 8, 18, 30, 24, 30, 30, 10, 10, 20, 20, 8, 24] }])
    end
  end
end
