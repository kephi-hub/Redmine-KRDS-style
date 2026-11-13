# 보안 취약점 진단 회차 — 도구·진단일·대상 리비전·진단자
class PmSecScan < ApplicationRecord
  belongs_to :project
  has_many :pm_sec_items, dependent: :delete_all

  validates :name, presence: true, length: { maximum: 100 }
  validates :tool, :scanner, length: { maximum: 60 }
  validates :revision, length: { maximum: 40 }

  scope :sorted, -> { order(Arel.sql('scanned_on IS NULL'), scanned_on: :desc, id: :desc) }

  def to_s
    name
  end
end
