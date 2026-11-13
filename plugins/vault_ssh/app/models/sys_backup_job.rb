# 시스템 백업 작업 하나 — 어느 서버(SSH 접속정보)에서 무엇을(DB 덤프 / 폴더) 언제(일정) 몇 번(보관) 받는지
class SysBackupJob < ApplicationRecord
  KINDS = %w(db files).freeze
  DB_KINDS = %w(mysql postgresql custom).freeze
  SCHEDULES = %w(off daily weekly).freeze

  belongs_to :project
  has_many :sys_backup_runs, -> { order(id: :desc) }, dependent: :destroy

  validates :name, presence: true, length: { maximum: 100 }
  validates :kind, inclusion: { in: KINDS }
  validates :schedule, inclusion: { in: SCHEDULES }
  validates :hour, inclusion: { in: 0..23 }
  validates :weekday, inclusion: { in: 1..7 }
  validates :keep, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 365 }
  validates :db_kind, inclusion: { in: DB_KINDS }, if: :db?
  validates :db_name, presence: true, if: -> { db? && db_kind != 'custom' }
  validates :dump_cmd, presence: true, if: -> { db? && db_kind == 'custom' }
  validates :db_port, numericality: { only_integer: true, greater_than: 0, less_than: 65_536 }, allow_nil: true
  validate :check_paths

  scope :sorted, -> { order(:name) }

  def db?
    kind == 'db'
  end

  def files?
    kind == 'files'
  end

  def ssh_key
    Vault::Key.find_by(id: vault_key_id, project_id: project_id)
  end

  def db_key
    db_key_id && Vault::Key.find_by(id: db_key_id, project_id: project_id)
  end

  def path_list
    paths.to_s.lines.map(&:strip).reject(&:empty?)
  end

  def exclude_list
    excludes.to_s.lines.map(&:strip).reject { |l| l.empty? || l.start_with?('#') }
  end

  def last_run
    sys_backup_runs.first
  end

  def last_done
    sys_backup_runs.where(status: 'done').first
  end

  def busy?
    sys_backup_runs.where(status: %w(queued running)).where('created_at > ?', 12.hours.ago).exists?
  end

  # 이 시각(서울 시간)에 일정상 돌아야 하는지 — 같은 시간대에 이미 돌았으면 아님
  def due?(now = Time.current.in_time_zone('Asia/Seoul'))
    return false unless active && schedule != 'off' && now.hour == hour
    return false if schedule == 'weekly' && now.to_date.cwday != weekday
    last_run_at.nil? || last_run_at < now - 50.minutes
  end

  private

  def check_paths
    return unless files?
    list = path_list
    errors.add(:paths, :blank) if list.empty?
    errors.add(:paths, I18n.t(:error_sb_path_abs)) if list.any? { |p| !p.start_with?('/') || p == '/' || p.include?('..') }
  end
end
