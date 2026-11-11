# 프로젝트 > 이슈·위험 — 관리대장, 가능성 × 영향 매트릭스, 엑셀
class PmRisksController < ApplicationController
  menu_item :risks
  helper :pm_docs
  include PmDocsHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_risk, only: [:show, :edit, :update, :destroy]

  def index
    all = PmRisk.where(project_id: @project.id).includes(:owner, :issue).sorted.to_a
    open = all.select(&:open?)
    @matrix = Hash.new(0)
    open.each { |r| @matrix[[r.probability, r.impact]] += 1 }
    @kpi = { all: all.size, open: open.size, high: open.count { |r| r.level == 'high' }, issue: open.count { |r| r.kind == 'issue' },
             late: open.count { |r| r.due_on && r.due_on < User.current.today } }
    @kind = params[:kind].presence_in(PmRisk::KINDS)
    @cell = params[:p].present? && params[:i].present? ? [params[:p].to_i, params[:i].to_i] : nil
    list = params[:all] == '1' ? all : open
    list = list.select { |r| r.kind == @kind } if @kind
    list = list.select { |r| [r.probability, r.impact] == @cell } if @cell
    list = list.select { |r| r.level == 'high' } if params[:level] == 'high'
    @risks = list
  end

  def show
  end

  def new
    @risk = PmRisk.new(project: @project, kind: params[:kind].presence_in(PmRisk::KINDS) || 'risk', raised_on: User.current.today, status: 'open')
    @members = pm_members(@project)
  end

  def create
    @risk = PmRisk.new(risk_params.merge(project: @project, author_id: User.current.id))
    if @risk.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to project_pm_risk_path(@project, @risk)
    else
      @members = pm_members(@project)
      render :new
    end
  end

  def edit
    @members = pm_members(@project)
  end

  def update
    @risk.assign_attributes(risk_params)
    @risk.closed_on ||= User.current.today if %w(closed).include?(@risk.status)
    if @risk.save
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_pm_risk_path(@project, @risk)
    else
      @members = pm_members(@project)
      render :edit
    end
  end

  def destroy
    @risk.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_pm_risks_path(@project)
  end

  def export
    send_data PmKit::Sheet.risks(PmRisk.where(project_id: @project.id).includes(:owner).order(:code).to_a),
              filename: "이슈위험관리대장_#{@project.identifier}_#{User.current.today.strftime('%Y%m%d')}.xlsx", type: PmKit::Sheet::XLSX
  end

  private

  def find_risk
    @risk = PmRisk.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def risk_params
    p = params.require(:pm_risk).permit(:code, :kind, :title, :description, :probability, :impact, :status, :owner_id, :plan, :due_on, :issue_id, :raised_on, :closed_on)
    p[:owner_id] = nil unless @project.users.exists?(id: p[:owner_id])
    iid = p[:issue_id].to_s[/\d+/]
    p[:issue_id] = iid && Issue.visible.where(project_id: @project.self_and_descendants.pluck(:id)).exists?(id: iid) ? iid.to_i : nil
    p
  end
end
