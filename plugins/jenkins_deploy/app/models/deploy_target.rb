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
  validate :job_path_safe, :default_params_format

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

  private

  def job_path_safe
    errors.add(:job_path, :invalid) if job_path.to_s.split('/').any? { |s| s.strip == '..' || s.strip == '.' }
  end

  def default_params_format
    bad = default_params.to_s.lines.map(&:strip).reject(&:blank?).reject { |l| l.match?(PARAM_LINE) }
    errors.add(:default_params, :invalid) if bad.any?
  end
end
