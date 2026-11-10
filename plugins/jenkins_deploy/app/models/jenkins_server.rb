# Jenkins 서버 접속 정보 — API 토큰은 Redmine 암호화 키(REDMINE_CIPHER_KEY)로 암호화해 저장
class JenkinsServer < ApplicationRecord
  has_many :deploy_targets, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: true
  validates :url, presence: true, length: { maximum: 255 }, format: { with: %r{\Ahttps?://[^\s/?#]+(/[^\s?#]*)?\z}i }
  validates :username, presence: true, length: { maximum: 120 }
  validates :timeout, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 60 }
  validates :token_encrypted, presence: { message: :blank }

  scope :sorted, -> { order(:name) }

  def token
    Redmine::Ciphering.decrypt_text(token_encrypted)
  end

  # 빈 값이면 기존 토큰 유지 (편집 화면에서 토큰을 다시 입력하지 않아도 됨)
  def token=(value)
    self.token_encrypted = Redmine::Ciphering.encrypt_text(value.to_s.strip) if value.present?
  end

  def token_set?
    token_encrypted.present?
  end

  def client
    JenkinsDeploy::Client.new(self)
  end

  def to_s
    name
  end
end
