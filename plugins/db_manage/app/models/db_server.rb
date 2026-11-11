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

  scope :sorted, -> { order(:name) }

  def self.adapter_options
    ADAPTERS.map { |k, (label, _, ok)| [ok ? label : "#{label} (준비 중)", k, { disabled: !ok, 'data-port' => ADAPTERS[k][1] }] }
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

  def address
    "#{host}:#{port}/#{database_name}"
  end

  def connector(schema = nil)
    DbManage::Connector.new(self, schema)
  end

  def to_s
    name
  end
end
