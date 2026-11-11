# 개인정보 컬럼 한 건 — 분류(고유식별·비밀번호·바이오·금융·민감·일반, 아님)와 암호화(양방향·단방향·미적용·미확인)
class DbPrivacyColumn < ApplicationRecord
  CATEGORIES = %w(unique_id password bio finance sensitive personal none).freeze
  ENCRYPTIONS = %w(two_way one_way none unknown).freeze
  # 암호화가 반드시 필요한 분류 (개인정보의 안전성 확보조치 기준: 고유식별정보·비밀번호·바이오정보, 계좌·카드번호 등)
  REQUIRED = %w(unique_id password bio finance).freeze

  belongs_to :db_link
  belongs_to :user, optional: true

  validates :table_name, :column_name, presence: true, length: { maximum: 128 }
  validates :category, inclusion: { in: CATEGORIES }
  validates :encryption, inclusion: { in: ENCRYPTIONS }
  validates :note, length: { maximum: 255 }
  validates :column_name, uniqueness: { scope: [:db_link_id, :table_name] }

  def key
    "#{table_name}.#{column_name}"
  end

  def personal?
    category != 'none'
  end

  # :ok / :warn(암호화 필요한데 미적용, 비밀번호가 단방향 아님) / :check(미확인) / :na(개인정보 아님)
  def judge
    DbPrivacyColumn.judge(category, encryption)
  end

  def self.judge(category, encryption)
    return :na if category == 'none'
    return :check if encryption == 'unknown'
    return :warn if category == 'password' && encryption != 'one_way'
    return :warn if REQUIRED.include?(category) && encryption == 'none'
    :ok
  end
end
