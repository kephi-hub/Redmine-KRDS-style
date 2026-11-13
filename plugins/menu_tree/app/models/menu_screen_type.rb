# 메뉴 구조도의 화면 유형 (프로젝트별) — code 는 menu_items.screen_type 에 저장되는 값, name 은 보이는 이름
# in_menu: 이 유형 화면의 "메뉴 노출" 기본값 (상세·등록·팝업·탭처럼 메뉴에 안 보이는 화면은 false)
# 프로젝트에 저장된 것이 없으면 기본 6가지
class MenuScreenType < ApplicationRecord
  DEFAULTS = [%w(list 1), %w(detail 0), %w(form 0), %w(popup 0), %w(tab 0), %w(link 1)].freeze
  Item = Struct.new(:code, :name, :in_menu, :id)

  belongs_to :project
  validates :name, presence: true, length: { maximum: 30 }
  validates :code, presence: true, length: { maximum: 20 }, uniqueness: { scope: :project_id }

  scope :sorted, -> { order(:position, :id) }

  def self.defaults
    DEFAULTS.map { |c, m| Item.new(c, I18n.t("label_menu_type_#{c}"), m == '1', nil) }
  end

  # 프로젝트의 화면 유형 목록 [Item]
  def self.for(project_id)
    rows = where(project_id: project_id).sorted.to_a
    rows.empty? ? defaults : rows.map { |r| Item.new(r.code, r.name, r.in_menu, r.id) }
  end

  def self.codes(project_id)
    self.for(project_id).map(&:code)
  end

  # { code => 이름 }
  def self.labels(project_id)
    self.for(project_id).to_h { |t| [t.code, t.name] }
  end

  # 메뉴 노출 기본값 (유형 없으면 노출)
  def self.in_menu?(project_id, code)
    return true if code.blank?
    t = self.for(project_id).find { |x| x.code == code }
    t ? t.in_menu : true
  end

  # 화면 유형 모달 저장 — list: [{code:, name:, in_menu:}] 순서대로. 빠진 유형을 쓰던 메뉴는 유형을 비움
  # 반환: [성공 여부, 오류 문구 또는 비운 메뉴 수]
  def self.replace(project, list)
    items = list.map { |h| { code: h[:code].to_s.strip.presence, name: h[:name].to_s.strip.truncate(30, omission: ''), in_menu: h[:in_menu].to_s == '1' } }
                .reject { |h| h[:name].blank? }
    return [false, I18n.t(:error_menu_types_empty)] if items.empty?
    names = items.map { |h| h[:name].downcase }
    return [false, I18n.t(:error_menu_types_dup, name: names.detect { |n| names.count(n) > 1 })] if names.uniq.size != names.size
    known = codes(project.id)
    items.each { |h| h[:code] = nil unless h[:code] && known.include?(h[:code]) }
    cleared = 0
    transaction do
      keep = items.map { |h| h[:code] }.compact
      gone = known - keep
      cleared = MenuItem.where(project_id: project.id, screen_type: gone).update_all(screen_type: nil) if gone.any?
      where(project_id: project.id).delete_all
      items.each_with_index do |h, i|
        code = h[:code] || "t#{SecureRandom.hex(4)}"
        create!(project: project, code: code, name: h[:name], in_menu: h[:in_menu], position: i + 1)
      end
    end
    [true, cleared]
  end
end
