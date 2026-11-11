# 메뉴 구조도 추가 칼럼 (프로젝트별) — 추가·수정·삭제
class MenuColumnsController < ApplicationController
  menu_item :menu_items
  before_action :find_project_by_project_id
  before_action :authorize

  def create
    col = MenuColumn.new(column_params.merge(project: @project, position: (MenuColumn.where(project_id: @project.id).maximum(:position) || 0) + 1))
    flash[col.save ? :notice : :error] = col.errors.any? ? col.errors.full_messages.join(', ') : l(:notice_successful_create)
    redirect_to project_menu_items_path(@project)
  end

  def update
    col = MenuColumn.find_by!(id: params[:id], project_id: @project.id)
    flash[col.update(column_params) ? :notice : :error] = col.errors.any? ? col.errors.full_messages.join(', ') : l(:notice_successful_update)
    redirect_to project_menu_items_path(@project)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # 칼럼을 지우면 메뉴에 들어 있던 값도 지움
  def destroy
    col = MenuColumn.find_by!(id: params[:id], project_id: @project.id)
    MenuColumn.transaction do
      MenuItem.where(project_id: @project.id).find_each do |m|
        next unless m.extra.key?(col.id.to_s)
        m.update_column(:extra, m.extra.except(col.id.to_s))
      end
      col.destroy
    end
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_menu_items_path(@project)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  private

  def column_params
    params.require(:menu_column).permit(:name, :kind, :options)
  end
end
