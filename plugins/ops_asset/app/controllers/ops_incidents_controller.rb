# 프로젝트 > 점검·장애 > 장애 — 발생·인지·복구 시각(중단 시간 자동), 등급, 원인·조치·재발 방지, 일감 연결
class OpsIncidentsController < ApplicationController
  menu_item :ops_incidents
  helper :ops_asset
  include OpsAssetHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_incident, only: [:show, :edit, :update, :destroy]

  def index
    all = OpsIncident.where(project_id: @project.id).includes(:ops_asset, :issue).sorted.to_a
    year = OpsKit::Cron.zone.now.beginning_of_year
    this_year = all.select { |i| i.occurred_at >= year }
    @kpi = { all: all.size, open: all.count { |i| i.status == 'open' }, year: this_year.size, downtime: this_year.sum { |i| i.downtime_min.to_i },
             grade1: this_year.count { |i| i.grade == '1' } }
    @status = params[:status].presence_in(OpsIncident::STATUSES)
    @incidents = @status ? all.select { |i| i.status == @status } : all
  end

  def show
  end

  def new
    @incident = OpsIncident.new(project: @project, occurred_at: OpsKit::Cron.zone.now.change(sec: 0), grade: '3')
  end

  def create
    @incident = OpsIncident.new(incident_params.merge(project: @project, author_id: User.current.id))
    if @incident.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to project_ops_incident_path(@project, @incident)
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @incident.update(incident_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_ops_incident_path(@project, @incident)
    else
      render :edit
    end
  end

  def destroy
    @incident.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_ops_incidents_path(@project)
  end

  private

  def find_incident
    @incident = OpsIncident.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # 시각은 서울 시간으로 입력 (datetime-local)
  def incident_params
    p = params.require(:ops_incident).permit(:title, :grade, :status, :occurred_at, :detected_at, :recovered_at, :ops_asset_id, :target, :impact,
                                             :cause, :action, :prevention, :issue_id)
    z = OpsKit::Cron.zone
    %i(occurred_at detected_at recovered_at).each { |k| p[k] = p[k].present? ? (z.parse(p[k]) rescue nil) : nil if p.key?(k) }
    p[:ops_asset_id] = nil unless OpsAsset.for_project(@project).exists?(id: p[:ops_asset_id])
    iid = p[:issue_id].to_s[/\d+/]
    p[:issue_id] = iid && Issue.visible.where(project_id: @project.self_and_descendants.pluck(:id)).exists?(id: iid) ? iid.to_i : nil
    p
  end
end
