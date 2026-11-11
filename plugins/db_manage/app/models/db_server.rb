# DB 서버 접속 정보 — 비밀번호는 Redmine 암호화 키(REDMINE_CIPHER_KEY)로 암호화해 저장
class DbServer < ApplicationRecord
  # 지원 DB 종류: 값 → [표시 이름, 기본 포트, 사용 가능 여부]
  ADAPTERS = {
    'mariadb' => ['MariaDB · MySQL', 3306, true],
    'postgresql' => ['PostgreSQL', 5432, true],
    'mssql' => ['MS SQL Server', 1433, false],
    'oracle' => ['Oracle', 1521, false]
  }.freeze

  has_many :db_links, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: true
  validates :adapter, inclusion: { in: ADAPTERS.select { |_, v| v[2] }.keys }
  validates :host, presence: true, length: { maximum: 255 }, format: { with: /\A[A-Za-z0-9._\-]+\z/ }
  validates :port, numericality: { only_integer: true, greater_than: 0, less_than: 65536 }
  validates :database_name, presence: true, length: { maximum: 128 }
  validates :username, presence: true, length: { maximum: 120 }
  validates :timeout, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 60 }
  validates :note, length: { maximum: 255 }
  validates :password_encrypted, presence: { message: :blank }
  # SSH 터널 (예: Redmine → WEB 서버 → DB)
  with_options if: :ssh_enabled? do
    validates :ssh_host, presence: true, length: { maximum: 255 }, format: { with: /\A[A-Za-z0-9._\-]+\z/ }
    validates :ssh_port, numericality: { only_integer: true, greater_than: 0, less_than: 65536 }
    validates :ssh_username, presence: true, length: { maximum: 120 }
    validates :ssh_auth, inclusion: { in: %w(password key) }
  end
  # (with_options 안에서 if: 를 다시 쓰면 바깥 조건을 덮어쓰므로 조건을 함께 적음)
  validates :ssh_password_encrypted, presence: { message: :blank }, if: -> { ssh_enabled? && ssh_auth == 'password' }
  validates :ssh_key_encrypted, presence: { message: :blank }, if: -> { ssh_enabled? && ssh_auth == 'key' }
  validate :ssh_key_readable, if: -> { ssh_enabled? && ssh_auth == 'key' && ssh_key_encrypted.present? }
  # 편집 화면 '지문 초기화' — 다음 연결 때 새 지문을 기록
  attr_accessor :ssh_reset_host_key
  before_save { self.ssh_host_key = nil if ssh_reset_host_key.to_s == '1' || ssh_host_changed? || ssh_port_changed? }

  scope :sorted, -> { order(:name) }

  def self.adapter_options
    ADAPTERS.map { |k, (label, _, ok)| [ok ? label : "#{label} (준비 중)", k, { disabled: !ok, 'data-port' => ADAPTERS[k][1] }] }
  end

  def env_label
    ::I18n.t(production? ? :label_db_production : :label_db_dev)
  end

  def adapter_label
    ADAPTERS.dig(adapter, 0) || adapter
  end

  def password
    Redmine::Ciphering.decrypt_text(password_encrypted)
  end

  # 빈 값이면 기존 비밀번호 유지 (편집 화면에서 다시 입력하지 않아도 됨)
  def password=(value)
    self.password_encrypted = Redmine::Ciphering.encrypt_text(value.to_s) if value.present?
  end

  def password_set?
    password_encrypted.present?
  end

  # SSH 비밀값: 빈 값이면 기존 값 유지
  def ssh_password
    Redmine::Ciphering.decrypt_text(ssh_password_encrypted)
  end

  def ssh_password=(value)
    self.ssh_password_encrypted = Redmine::Ciphering.encrypt_text(value.to_s) if value.present?
  end

  def ssh_private_key
    Redmine::Ciphering.decrypt_text(ssh_key_encrypted)
  end

  def ssh_private_key=(value)
    self.ssh_key_encrypted = Redmine::Ciphering.encrypt_text(value.to_s.strip + "\n") if value.present?
  end

  def ssh_passphrase
    Redmine::Ciphering.decrypt_text(ssh_passphrase_encrypted)
  end

  def ssh_passphrase=(value)
    self.ssh_passphrase_encrypted = Redmine::Ciphering.encrypt_text(value.to_s) if value.present?
  end

  def ssh_route
    "#{ssh_username}@#{ssh_host}:#{ssh_port}" if ssh_enabled?
  end

  def address
    "#{host}:#{port}/#{database_name}"
  end

  def connector(schema = nil)
    DbManage::Connector.new(self, schema)
  end

  def to_s
    name
  end

  private

  # 개인키 형식·암호 구문 확인 (OpenSSH·PEM, ed25519·RSA·ECDSA)
  def ssh_key_readable
    require 'net/ssh'
    Net::SSH::KeyFactory.load_data_private_key(ssh_private_key, ssh_passphrase.presence, false)
  rescue LoadError
    nil
  rescue StandardError
    errors.add(:ssh_key_encrypted, :invalid)
  end
end
