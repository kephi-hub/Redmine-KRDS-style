# 관리 > 메뉴·모듈 이름 — 화면에 보이는 이름만 바꿈 (비우면 기본 이름)
class KrdsLabelsController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :krds_labels

  before_action :require_admin

  def index
    @catalog = KrdsUi::Labels.catalog
    @saved = KrdsLabel.all.to_a.index_by { |r| "#{r.kind}:#{r.key}" }
  end

  def save
    valid = KrdsUi::Labels.catalog.to_h { |kind, _, list| [kind, list.map(&:first)] }
    changed = 0
    KrdsLabel.transaction do
      (params[:labels] || {}).to_unsafe_h.each do |kind, values|
        next unless valid.key?(kind)
        values.each do |key, name|
          next unless valid[kind].include?(key)
          name = name.to_s.strip.truncate(60, omission: '')
          rec = KrdsLabel.find_by(kind: kind, key: key)
          if name.empty?
            (rec.destroy; changed += 1) if rec
          elsif rec.nil? || rec.name != name
            (rec || KrdsLabel.new(kind: kind, key: key)).update!(name: name)
            changed += 1
          end
        end
      end
    end
    flash[:notice] = changed.positive? ? l(:notice_krds_labels_saved, :count => changed) : l(:notice_krds_labels_same)
    redirect_to krds_labels_path
  end

  def reset
    n = KrdsLabel.delete_all
    flash[:notice] = l(:notice_krds_labels_reset, :count => n)
    redirect_to krds_labels_path
  end
end
