# 프로젝트마다 추가하는 메뉴 칼럼 (텍스트·선택 목록·체크·날짜). 값은 menu_items.extra[칼럼 id]
class MenuColumn < ApplicationRecord
  KINDS = %w(text list bool date).freeze

  belongs_to :project
  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :project_id, case_sensitive: false }
  validates :kind, inclusion: { in: KINDS }

  scope :sorted, -> { order(:position, :id) }

  def option_list
    options.to_s.split(/\r?\n/).map(&:strip).reject(&:blank?).uniq
  end

  # 입력값 정리 (목록에 없는 값·잘못된 날짜는 빈 값)
  def cast(value)
    v = value.to_s.strip
    case kind
    when 'bool' then %w(1 true Y y on 예 O o).include?(v) ? '1' : nil
    when 'date' then (Date.parse(v).strftime('%Y-%m-%d') rescue nil)
    when 'list' then option_list.include?(v) ? v : (v.presence && option_list.empty? ? v : nil)
    else v.presence&.truncate(1000)
    end
  end
end
