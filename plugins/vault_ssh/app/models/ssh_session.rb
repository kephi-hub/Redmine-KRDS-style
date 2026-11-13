# 브라우저 터미널 접속 한 번 — 누가·언제·어느 서버·사유·시간·종료 사유·녹화 파일
class SshSession < ApplicationRecord
  STATUSES = %w(pending running closed failed).freeze

  belongs_to :project
  belongs_to :user
  belongs_to :key, class_name: 'Vault::Key', optional: true

  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def self.root
    Pathname.new(Redmine::Configuration['attachments_storage_path'].presence || Rails.root.join('files').to_s).join('ssh_records')
  end

  def record_path
    record_file.present? ? self.class.root.join(record_file) : nil
  end

  def prod?
    env == 'prod'
  end

  # 지금 이 서버 프로세스에서 돌고 있는지 (재시작으로 끊긴 기록 구분)
  def live?
    SshConsole::Runner.get(id).present?
  end

  def duration
    return nil unless started_at
    ((ended_at || Time.current) - started_at).to_i
  end

  after_destroy { File.delete(record_path) if record_path && File.file?(record_path) }
end
