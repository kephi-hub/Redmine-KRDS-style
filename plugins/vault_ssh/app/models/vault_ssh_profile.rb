# 접속정보(Vault) "SSH 서버" 의 SSH 설정 — 포트 · 인증 · 경유 서버 · 지문 · 시작 명령 · 구분 · 녹화
# 직접 입력한 비밀값은 Redmine::Ciphering(REDMINE_CIPHER_KEY) 로 암호화
class VaultSshProfile < ApplicationRecord
  AUTHS = %w(password key ask).freeze
  ENVS = %w(dev prod).freeze
  MAX_HOPS = 3

  belongs_to :key, class_name: 'Vault::Key'

  validates :auth, inclusion: { in: AUTHS }
  validates :env, inclusion: { in: ENVS }
  validates :port, numericality: { only_integer: true, greater_than: 0, less_than: 65_536 }, allow_nil: true
  validates :start_cmd, length: { maximum: 255 }
  validate :check_hops

  def self.for(key)
    find_or_initialize_by(key_id: key.id)
  end

  def self.encrypt(v)
    v.present? ? Redmine::Ciphering.encrypt_text(v) : nil
  end

  def self.decrypt(v)
    v.present? ? Redmine::Ciphering.decrypt_text(v) : nil
  end

  def hop_list
    JSON.parse(hops.presence || '[]')
  rescue JSON::ParserError
    []
  end

  def hop_list=(list)
    self.hops = Array(list).first(MAX_HOPS).to_json
  end

  def key_pass
    self.class.decrypt(key_pass_enc)
  end

  def prod?
    env == 'prod'
  end

  private

  def check_hops
    list = hop_list
    errors.add(:base, :invalid) if list.size > MAX_HOPS
    list.each do |h|
      next if h['key_id'].present?
      errors.add(:base, I18n.t(:error_ssh_hop_host)) if h['host'].blank?
      errors.add(:base, I18n.t(:error_ssh_hop_host)) if h['port'].present? && !h['port'].to_i.between?(1, 65_535)
    end
    errors.add(:base, I18n.t(:error_ssh_key_file)) if auth == 'key' && key_file_id.blank?
  end
end
