# 크론 표현식 해석 — 한국어 풀이와 다음 실행 시각 (서버 시간대: 서울)
# - 5칸(분 시 일 월 요일, crontab·pg_cron), 6~7칸(초 분 시 일 월 요일 [연], Spring·Quartz), @daily 같은 줄임말
# - Quartz 는 요일 1=일요일, 나머지는 0·7=일요일. Jenkins 의 H 는 0 으로 보고 계산(대략)
# - L·W·# 는 계산하지 않음(풀이만 원문)
module OpsKit
  class Cron
    MACROS = { '@yearly' => '0 0 1 1 *', '@annually' => '0 0 1 1 *', '@monthly' => '0 0 1 * *', '@weekly' => '0 0 * * 0',
               '@daily' => '0 0 * * *', '@midnight' => '0 0 * * *', '@hourly' => '0 * * * *' }.freeze
    MONTHS = %w(JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC).freeze
    DAYS = %w(SUN MON TUE WED THU FRI SAT).freeze
    DAY_KO = %w(일 월 화 수 목 금 토).freeze
    ZONE = 'Asia/Seoul'.freeze

    attr_reader :error, :approx, :raw

    def self.zone
      ActiveSupport::TimeZone[ZONE]
    end

    def initialize(expr, quartz: false)
      @raw = expr.to_s.strip
      @approx = false
      e = MACROS[@raw.downcase] || @raw
      return @error = :reboot if @raw.downcase == '@reboot'
      return @error = :empty if e.empty?
      if e.match?(/\bH\b|H\(|H\//)
        @approx = true
        e = e.gsub(/H\(\s*(\d+)\s*-\s*\d+\s*\)/, '\1').gsub('H', '0')
      end
      parts = e.split(/\s+/)
      case parts.size
      when 5 then sec = '0'; min, hour, dom, mon, dow = parts
      when 6, 7
        sec, min, hour, dom, mon, dow, year = parts
        @approx = true if year && year != '*'
      else return @error = :format
      end
      return @error = :unsupported if [dom, dow].any? { |f| f.upcase.match?(/#|\d[LW]|\AL|,L|LW/) }
      dom = '*' if dom == '?'
      dow = '*' if dow == '?'
      @sec = expand(sec, 0, 59)
      @min = expand(min, 0, 59)
      @hour = expand(hour, 0, 23)
      @dom = expand(dom, 1, 31)
      @mon = expand(mon, 1, 12, MONTHS, 1)
      @dow = if quartz
               expand(dow, 1, 7, DAYS, 1).map { |d| d - 1 }
             else
               expand(dow, 0, 7, DAYS, 0).map { |d| d % 7 }.uniq.sort
             end
      @dom_all = dom == '*'
      @dow_all = dow == '*'
    rescue ArgumentError, TypeError
      @error = :format
    end

    def valid?
      @error.nil?
    end

    # 다음 실행 n번 (from 이후, 최대 400일 앞까지)
    def next_runs(from = Time.now, n = 5)
      return [] unless valid?
      z = self.class.zone
      from = from.in_time_zone(z)
      out = []
      (0..400).each do |i|
        d = from.to_date + i
        next unless day?(d)
        @hour.each do |h|
          @min.each do |m|
            @sec.each do |s|
              t = z.local(d.year, d.month, d.day, h, m, s)
              next if t <= from
              out << t
              return out if out.size >= n
            end
          end
        end
      end
      out
    end

    # 그날 실행 시각 (최대 limit 개)
    def runs_on(date, limit = 1500)
      return [] unless valid? && day?(date)
      z = self.class.zone
      out = []
      @hour.each { |h| @min.each { |m| @sec.each { |s| out << z.local(date.year, date.month, date.day, h, m, s); return out if out.size >= limit } } }
      out
    end

    def day?(d)
      return false unless @mon.include?(d.month)
      dom_ok = @dom.include?(d.day)
      dow_ok = @dow.include?(d.wday)
      if @dom_all && @dow_all then true
      elsif @dom_all then dow_ok
      elsif @dow_all then dom_ok
      else dom_ok || dow_ok
      end
    end

    # 한국어 풀이: "매일 02:00", "매주 월·금 09:30", "15분마다", "매월 1일 00:00"
    def describe
      return { reboot: '서버 시작 때', empty: '-', unsupported: "#{@raw} (L·W·# 는 풀이하지 않음)", format: '형식 오류' }[@error] if @error
      parts = []
      parts << "#{@mon.join('·')}월" if @mon.size < 12
      day = day_text
      time = time_text
      # "매일 15분마다" 처럼 하루에 여러 번이면 "매일" 은 빼고
      parts << day unless day == '매일' && !time.match?(/\A\d{2}:\d{2}/)
      parts << time
      parts << "(#{@sec.join('·')}초)" unless @sec == [0]
      text = parts.reject(&:blank?).join(' ')
      @approx ? "#{text} (대략)" : text
    end

    private

    def day_text
      if @dom_all && @dow_all then '매일'
      elsif @dom_all then @dow == [1, 2, 3, 4, 5] ? '평일' : "매주 #{@dow.map { |d| DAY_KO[d] }.join('·')}"
      elsif @dow_all then "매월 #{@dom.join('·')}일"
      else "매월 #{@dom.join('·')}일 또는 #{@dow.map { |d| DAY_KO[d] }.join('·')}요일"
      end
    end

    def time_text
      all_min = @min.size == 60
      all_hour = @hour.size == 24
      return '매분' if all_min && all_hour
      return "#{@hour.map { |h| format('%02d', h) }.join('·')}시 매분" if all_min
      if all_hour
        step = step_of(@min, 60)
        return step ? "#{step}분마다" : "매시 #{@min.join('·')}분"
      end
      if (step = step_of(@min, 60)) && @hour == (@hour.first..@hour.last).to_a
        return "#{format('%02d', @hour.first)}~#{format('%02d', @hour.last)}시 #{step}분마다"
      end
      if @hour.size * @min.size <= 6
        @hour.flat_map { |h| @min.map { |m| format('%02d:%02d', h, m) } }.join('·')
      elsif @min.size == 1 && (step = step_of(@hour, 24))
        "#{step}시간마다 #{format('%02d', @min.first)}분"
      else
        "하루 #{@hour.size * @min.size}회 (#{@hour.join('·')}시)"
      end
    end

    # 0 부터 일정 간격으로 끝까지 가면 그 간격
    def step_of(list, size)
      return nil if list.size < 2 || list.first != 0
      step = list[1] - list[0]
      list == (0...size).step(step).to_a ? step : nil
    end

    def expand(field, lo, hi, names = nil, name_base = 0)
      field.to_s.upcase.split(',').flat_map do |part|
        names&.each_with_index { |n, i| part = part.gsub(n, (i + name_base).to_s) }
        base, step = part.split('/', 2)
        step = step ? Integer(step) : 1
        raise ArgumentError if step <= 0
        a, b = if base == '*' then [lo, hi]
               elsif base.include?('-') then base.split('-', 2).map { |x| Integer(x) }
               else [Integer(base), part.include?('/') ? hi : Integer(base)]
               end
        raise ArgumentError unless a.between?(lo, hi) && b.between?(lo, hi) && a <= b
        (a..b).step(step).to_a
      end.uniq.sort
    end
  end
end
