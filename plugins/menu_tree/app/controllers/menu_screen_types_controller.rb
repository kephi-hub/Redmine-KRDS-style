# 메뉴 구조도 화면 유형 (프로젝트별) — 모달에서 목록 통째로 저장
class MenuScreenTypesController < ApplicationController
  menu_item :menu_items
  before_action :find_project_by_project_id
  before_action :authorize

  def save
    raw = params.permit(types: [:code, :name, :in_menu])[:types]
    raw = raw.to_h.sort_by { |k, _| k.to_i }.map(&:last) if raw.respond_to?(:keys)
    list = Array(raw).map { |h| h.to_h.symbolize_keys }
    ok, info = MenuScreenType.replace(@project, list)
    if ok
      flash[:notice] = info.positive? ? l(:notice_menu_types_cleared, count: info) : l(:notice_successful_update)
    else
      flash[:error] = info
    end
    redirect_to project_menu_items_path(@project, site: params[:site].presence)
  end
end
