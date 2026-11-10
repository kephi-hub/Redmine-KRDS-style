# 접속정보 유형 — 이름, 입력 방식(Vault 기본 유형), 순서
class VaultKeyType < ApplicationRecord
  BASES = { 'Vault::Password' => :label_vault_base_password, 'Vault::Sftp' => :label_vault_base_sftp,
            'Vault::KeyFile' => :label_vault_base_key_file }.freeze

  has_many :keys, class_name: 'Vault::Key', foreign_key: :vault_type_id, dependent: :restrict_with_error

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: true
  validates :base_type, inclusion: { in: BASES.keys }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 999 }

  scope :sorted, -> { order(:position, :name) }

  def base_label
    I18n.t(BASES[base_type])
  end

  def to_s
    name
  end
end
