# 프로젝트의 배포 환경 (예: 개발서버 → Jenkins 작업 mainbiz/dev-deploy)
class DeployTarget < ApplicationRecord
  belongs_to :project
  belongs_to :jenkins_server
  has_many :deploy_runs, dependent: :nullify

  PARAM_LINE = /\A([A-Za-z_][A-Za-z0-9_]*)=(.*)\z/

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
