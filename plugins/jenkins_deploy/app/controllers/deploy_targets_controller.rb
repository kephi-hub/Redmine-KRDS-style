# 프로젝트 > 설정 > 배포 — 배포 환경 추가·수정·삭제
class DeployTargetsController < ApplicationController
  menu_item :settings

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_target, only: [:edit, :update, :destroy]

  def new
    @target = @project.deploy_targets.build
  end

  def create
    @target = @project.deploy_targets.build(target_params)
    if @target.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to settings_project_path(@project, tab: 'deploys')
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @target.update(target_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to settings_project_path(@project, tab: 'deploys')
    else
      render :edit
    end
  end

  def destroy
    @target.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to settings_project_path(@project, tab: 'deploys')
  end

  private

  def find_target
    @target = @project.deploy_targets.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def target_params
    params.require(:deploy_target).permit(:name, :jenkins_server_id, :job_path, :production, :default_params)
  end
end
