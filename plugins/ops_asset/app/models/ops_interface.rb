# 연계 인터페이스 — ID 비워 두면 IF-001 처럼 자동
class OpsInterface < ApplicationRecord
  DIRECTIONS = %w(send recv both).freeze
  PROTOCOLS = %w(rest soap db_link sftp mq batch other).freeze
  CYCLES = %w(realtime schedule manual).freeze
  STATUSES = %w(active dev stopped).freeze

  belongs_to :project
  belongs_to :ops_schedule, optional: true

  validates :name, presence: true, length: { maximum: 150 }
  validates :partner, presence: true, length: { maximum: 120 }
  validates :direction, inclusion: { in: DIRECTIONS }
  validates :protocol, inclusion: { in: PROTOCOLS }
  validates :cycle, inclusion: { in: CYCLES }
  validates :status, inclusion: { in: STATUSES }
  validates :code, presence: true, length: { maximum: 30 }, format: { with: /\A[A-Za-z0-9][A-Za-z0-9_.\-]*\z/ },
                   uniqueness: { scope: :project_id, case_sensitive: false }
  validates :dev_url, :prod_url, :partner_contact, :auth_note, length: { maximum: 255 }
  validate :schedule_in_project

  before_validation :fill_code

  scope :sorted, -> { order(:code) }

  def self.next_code(project)
    nums = where(project_id: project.id).where('code LIKE ?', 'IF-%').pluck(:code).map { |c| c[/\AIF-(\d+)/, 1].to_i }
    format('IF-%03d', (nums.max || 0) + 1)
  end

  def fill_code
    self.code = code.to_s.strip.upcase.presence
    self.name = name.to_s.strip
    self.partner = partner.to_s.strip
    self.code ||= self.class.next_code(project) if project
  end

  def schedule_in_project
    errors.add(:ops_schedule_id, :invalid) if ops_schedule && ops_schedule.project_id != project_id
  end
end
