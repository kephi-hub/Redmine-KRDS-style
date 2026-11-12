# SR(서비스 요청) 처리 기한 — 완료 기한을 비워 두고 저장하면 긴급도로 자동 (영업일, 주말 제외)
#   긴급: 당일 · 높음: 1일 · 보통: 3일 · 낮음: 5일 (시작일 기준, 없으면 오늘)
# 기한 준수(SLA): 닫힌 날짜 ≤ 완료 기한 — 대시보드 · 월간 보고서
module PmKit
  module Sla
    TRACKER = 'SR'
    FIELD = '긴급도'
    DAYS = { '긴급' => 0, '높음' => 1, '보통' => 3, '낮음' => 5 }.freeze

    module_function

    def field
      IssueCustomField.find_by(name: FIELD)
    end

    def add_business_days(date, n)
      d = date
      d += 1 while d.saturday? || d.sunday?
      n.times do
        d += 1
        d += 1 while d.saturday? || d.sunday?
      end
      d
    end

    # Issue before_validation 에서 부름
    def fill_due(issue)
      return unless issue.tracker&.name == TRACKER && issue.due_date.blank?
      cf = field
      days = cf && DAYS[issue.custom_field_value(cf).to_s]
      return unless days
      issue.due_date = add_business_days(issue.start_date || User.current.today, days)
    end
  end
end
