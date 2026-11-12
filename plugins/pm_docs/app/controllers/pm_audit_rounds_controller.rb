# 프로젝트 > 감리 > 감리 회차 — 이름·단계·기간·감리 기관
class PmAuditRoundsController < ApplicationController
  menu_item :audits
  helper :pm_docs
  include PmDocsHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_round, only: [:edit, :update, :destroy]

  def new
    @round = PmAuditRound.new(project: @project)
  end

  def create
    @round = PmAuditRound.new(round_params.merge(project: @project))
    if @round.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to project_pm_audits_path(@project, round: @round.id)
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @round.update(round_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_pm_audits_path(@project, round: @round.id)
    else
      render :edit
    end
  end

  # 지적사항이 남아 있으면 지울 수 없음
  def destroy
    if @round.destroy
      flash[:notice] = l(:notice_successful_delete)
    else
      flash[:error] = l(:error_pm_round_not_empty)
    end
    redirect_to project_pm_audits_path(@project)
  end

  private

  def find_round
    @round = PmAuditRound.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def round_params
    params.require(:pm_audit_round).permit(:name, :phase, :start_on, :end_on, :auditor, :note)
  end
end
