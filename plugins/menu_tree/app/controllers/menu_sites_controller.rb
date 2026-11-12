# 메뉴 구조도 사이트 (예: 사용자 페이지 · 관리자 페이지) — 추가·수정·삭제 (메뉴 구조도 편집 권한)
class MenuSitesController < ApplicationController
  menu_item :menu_items
  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_site, only: [:update, :destroy]

  def create
    site = MenuSite.new(site_params.merge(project: @project, position: (MenuSite.where(project_id: @project.id).maximum(:position) || 0) + 1))
    if site.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to project_menu_items_path(@project, site: site.id)
    else
      flash[:error] = site.errors.full_messages.join(', ')
      redirect_to project_menu_items_path(@project)
    end
  end

  def update
    flash[@site.update(site_params) ? :notice : :error] = @site.errors.any? ? @site.errors.full_messages.join(', ') : l(:notice_successful_update)
    redirect_to project_menu_items_path(@project, site: @site.id)
  end

  # 메뉴가 남아 있는 사이트는 지울 수 없음 (메뉴를 다른 사이트로 옮기거나 지운 뒤)
  def destroy
    if @site.destroy
      flash[:notice] = l(:notice_successful_delete)
    else
      flash[:error] = l(:error_menu_site_not_empty, count: @site.menu_items.count)
    end
    redirect_to project_menu_items_path(@project)
  end

  private

  def find_site
    @site = MenuSite.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def site_params
    params.require(:menu_site).permit(:name, :code, :url, :description, :position)
  end
end
