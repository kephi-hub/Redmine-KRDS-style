# 점검표 양식 — 항목은 한 줄에 하나
class OpsCheckTemplate < ApplicationRecord
  belongs_to :project
  validates :name, presence: true, length: { maximum: 100 }

  def item_list
    items.to_s.lines.map(&:strip).reject(&:empty?)
  end
end
