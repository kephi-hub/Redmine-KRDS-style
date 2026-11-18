# 프로젝트의 배포 환경 (예: 개발서버 → Jenkins 작업 mainbiz/dev-deploy)
class DeployTarget < ApplicationRecord
  belongs_to :project
  belongs_to :jenkins_server
  has_many :deploy_runs, dependent: :nullify

  PARAM_LINE = /\A([A-Za-z_][A-Za-z0-9_]*)=(.*)\z/
  AUTO_PARAMS = %w(REDMINE_USER REDMINE_RUN_ID).freeze

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :project_id }
  validates :job_path, presence: true, length: { maximum: 255 },
                       format: { with: %r{\A[^/\s][^/]*(/[^/]+)*\z} }
  validate :job_path_safe, :default_params_format, :window_format

  TIME_RE = /\A([01]\d|2[0-3]):[0-5]\d\z/
  ZONE = 'Asia/Seoul'

  scope :sorted, -> { order(:production, :name) }

  # "이름=값" 줄 → Hash
  def params_hash
    default_params.to_s.lines.map(&:strip).reject(&:blank?).each_with_object({}) do |line, h|
      m = line.match(PARAM_LINE) and h[m[1]] = m[2]
    end
  end

  # 배포 확인창에서 고를 수 있는 매개변수 (자동 매개변수·비밀번호 제외)
  def selectable_params(definitions)
    Array(definitions).reject { |d| AUTO_PARAMS.include?(d[:name]) || d[:type].include?('Password') }
  end

  # 확인창 초기값: 이 환경의 기본 매개변수 > Jenkins 기본값
  def initial_value(definition)
    params_hash.key?(definition[:name]) ? params_hash[definition[:name]] : definition[:default]
  end

  # 실제로 Jenkins 에 보낼 값: 기본 매개변수 + 확인창에서 고른 값 (Jenkins 에 정의된 것만, 선택지 검사)
  def run_params(definitions, input)
    input = input.respond_to?(:to_unsafe_h) ? input.to_unsafe_h : input.to_h
    values = params_hash
    selectable_params(definitions).each do |d|
      next unless input.key?(d[:name])
      v = input[d[:name]].to_s
      if d[:type].include?('Boolean')
        v = v == 'true' ? 'true' : 'false'
      elsif d[:choices].any? && !d[:choices].include?(v)
        raise ArgumentError, I18n.t(:error_deploy_bad_choice, name: d[:name])
      end
      values[d[:name]] = v.truncate(1000, omission: '')
    end
    values
  end

  def required_permission
    production? ? :run_production_deploys : :run_deploys
  end

  def runnable_by?(user = User.current)
    user.allowed_to?(required_permission, project)
  end

  def active_run
    deploy_runs.active.order(:id).last
  end

  # ---- 배포 가능 시간 (서울 시간, 요일은 1=월 … 7=일, 끝이 시작보다 이르면 자정을 넘김) ----
  def day_list
    window_days.to_s.split(',').map(&:to_i).select { |d| (1..7).cover?(d) }.uniq.sort
  end

  def day_list=(list)
    self.window_days = Array(list).map(&:to_i).select { |d| (1..7).cover?(d) }.uniq.sort.join(',')
  end

  def window_minutes
    [window_start, window_end].map { |t| h, m = t.to_s.split(':').map(&:to_i); h.to_i * 60 + m.to_i }
  end

  # 지금(또는 주어진 시각) 배포할 수 있는지
  def deploy_open?(now = Time.current)
    return true unless window_enabled?
    t = now.in_time_zone(ZONE)
    s, e = window_minutes
    cur = t.hour * 60 + t.min
    if s <= e
      day_list.include?(t.to_date.cwday) && cur >= s && cur < e
    else # 자정을 넘김: 시작 요일 기준 — 시작 이후는 오늘, 끝 이전은 어제가 허용 요일이어야 함
      (cur >= s && day_list.include?(t.to_date.cwday)) || (cur < e && day_list.include?((t.to_date - 1).cwday))
    end
  end

  # 다음 배포 가능 시작 시각 (최대 8일 앞까지)
  def next_open_at(now = Time.current)
    return nil unless window_enabled? && day_list.any?
    t = now.in_time_zone(ZONE)
    s, = window_minutes
    (0..8).each do |i|
      d = t.to_date + i
      next unless day_list.include?(d.cwday)
      start = Time.find_zone(ZONE).local(d.year, d.month, d.day, s / 60, s % 60)
      return start if start > t
    end
    nil
  end

  # "평일 18:00~22:00" · "월·수·금 22:00~익일 06:00"
  def window_text
    names = I18n.t(:label_deploy_weekdays).split(',')
    days = case day_list
           when [1, 2, 3, 4, 5] then I18n.t(:label_deploy_days_weekday)
           when (1..7).to_a then I18n.t(:label_deploy_days_every)
           when [6, 7] then I18n.t(:label_deploy_days_weekend)
           else day_list.map { |d| names[d - 1] }.join('·')
           end
    s, e = window_minutes
    "#{days} #{window_start}~#{s > e ? I18n.t(:label_deploy_next_day) + ' ' : ''}#{window_end}"
  end

  private

  def job_path_safe
    errors.add(:job_path, :invalid) if job_path.to_s.split('/').any? { |s| s.strip == '..' || s.strip == '.' }
  end

  def window_format
    return unless window_enabled?
    errors.add(:window_days, :blank) if day_list.empty?
    errors.add(:window_start, :invalid) unless window_start.to_s.match?(TIME_RE)
    errors.add(:window_end, :invalid) unless window_end.to_s.match?(TIME_RE)
    errors.add(:window_end, :invalid) if window_start == window_end
  end

  def default_params_format
    bad = default_params.to_s.lines.map(&:strip).reject(&:blank?).reject { |l| l.match?(PARAM_LINE) }
    errors.add(:default_params, :invalid) if bad.any?
  end
end
