# 프로젝트 > 설정 > DB — 이 프로젝트에서 쓰는 DB(개발DB·운영DB 등) 추가·수정·삭제
class DbLinksController < ApplicationController
  menu_item :settings

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_link, only: [:edit, :update, :destroy]

  def new
    # 처음 고른 DB 서버의 개발/운영 구분을 기본값으로
    server = DbServer.sorted.first
    @link = @project.db_links.build(name: @project.db_links.empty? ? '개발DB' : '운영DB', db_server: server, production: server&.production? || false)
  end

  def create
    @link = @project.db_links.build(link_params)
    @link.position = (@project.db_links.maximum(:position) || 0) + 1
    if @link.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to settings_project_path(@project, tab: 'db_links')
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @link.update(link_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to settings_project_path(@project, tab: 'db_links')
    else
      render :edit
    end
  end

  def destroy
    @link.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to settings_project_path(@project, tab: 'db_links')
  end

  private

  def find_link
    @link = @project.db_links.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def link_params
    params.require(:db_link).permit(:name, :db_server_id, :schema_name, :production)
  end
end
