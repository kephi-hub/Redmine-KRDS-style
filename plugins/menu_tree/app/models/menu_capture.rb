# 화면 캡처 한 장 — 메뉴(화면) × PC/모바일 × 시각. 파일은 files/menu_captures/<프로젝트>/<메뉴>/ (PMS 백업에 포함)
class MenuCapture < ApplicationRecord
  KINDS = %w(pc mobile).freeze

  belongs_to :project
  belongs_to :menu_item
  belongs_to :menu_capture_run, optional: true

  scope :ok, -> { where(status: 'ok') }

  def self.root
    Pathname.new(Redmine::Configuration['attachments_storage_path'].presence || Rails.root.join('files').to_s).join('menu_captures')
  end

  def path
    file && self.class.root.join(file)
  end

  def thumb_path
    thumb && self.class.root.join(thumb)
  end

  def ok?
    status == 'ok'
  end

  # 웹 접근성 위반 목록 (점검 안 했으면 nil) — MenuTree::A11y.check 결과
  def a11y_list
    return nil if a11y.nil?
    JSON.parse(a11y) rescue []
  end

  # 위반 요소 수 합계
  def a11y_nodes
    (a11y_list || []).sum { |v| v['n'].to_i }
  end

  # 파일도 함께 지움
  after_destroy do
    [path, thumb_path].compact.each { |pa| File.delete(pa) if File.file?(pa) }
  end
end
