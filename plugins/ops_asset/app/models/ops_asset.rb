# 인프라 자산 — 서버·도메인·SSL 인증서·라이선스·클라우드·장비. project_id 가 없으면 공용(관리자), 있으면 그 프로젝트 자산
class OpsAsset < ApplicationRecord
  KINDS = %w(server domain cert license cloud device).freeze
  ENVS = %w(prod dev test common).freeze
  ALERT_DAYS = [30, 7, 1, 0].freeze

  belongs_to :project, optional: true
  has_many :ops_asset_links, dependent: :delete_all
  has_many :linked_projects, through: :ops_asset_links, source: :project
  has_many :ops_schedules, dependent: :nullify

  validates :name, presence: true, length: { maximum: 120 }
  validates :kind, inclusion: { in: KINDS }
  validates :env, inclusion: { in: ENVS }
  validates :address, :renew_cycle, :vendor, :owner, length: { maximum: 255 }

  before_validation { self.name = name.to_s.strip }

  scope :sorted, -> { order(:kind, :name) }

  # 프로젝트에서 보이는 자산: 그 프로젝트 자산 + 연결된 공용 자산
  def self.for_project(project)
    where(project_id: project.id).or(where(id: OpsAssetLink.where(project_id: project.id).select(:ops_asset_id)))
  end

  def shared?
    project_id.nil?
  end

  def days_left(today = Date.current)
    expires_on && (expires_on - today).to_i
  end

  # :expired / :soon7 / :soon30 / :ok / :none
  def expiry_state(today = Date.current)
    d = days_left(today)
    return :none if d.nil? || !active?
    return :expired if d.negative?
    return :soon7 if d <= 7
    return :soon30 if d <= 30
    :ok
  end

  def db_server
    defined?(DbServer) && db_server_id ? DbServer.find_by(id: db_server_id) : nil
  end

  def jenkins_server
    defined?(JenkinsServer) && jenkins_server_id ? JenkinsServer.find_by(id: jenkins_server_id) : nil
  end

  # 서버 정보 수집에 쓰는 SSH 접속정보 (접속정보 vault_ssh 의 "SSH 서버")
  def vault_key
    defined?(Vault::Key) && vault_key_id ? Vault::Key.find_by(id: vault_key_id) : nil
  end

  def server_info_h
    server_info.present? ? JSON.parse(server_info) : nil
  rescue JSON::ParserError
    nil
  end

  def cert_info_h
    cert_info.present? ? JSON.parse(cert_info) : nil
  rescue JSON::ParserError
    nil
  end

  def disk_warn?
    disk_pct.to_i >= OpsKit::Probe::DISK_WARN
  end

  def cert_checkable?
    %w(cert domain).include?(kind) && address.present?
  end

  def to_s
    name
  end
end
