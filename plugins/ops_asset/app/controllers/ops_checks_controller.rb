# 프로젝트 > 점검·장애 > 정기점검 — 점검표 양식으로 회차를 만들고 항목별 정상·이상·해당 없음과 조치 기록
class OpsChecksController < ApplicationController
  menu_item :ops_incidents
  helper :ops_asset
  include OpsAssetHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_check, only: [:show, :edit, :update, :destroy]

  def index
    @checks = OpsCheck.where(project_id: @project.id).includes(:user, :ops_check_template).sorted.to_a
    @templates = OpsCheckTemplate.where(project_id: @project.id).order(:name).to_a
  end

  def show
  end

  def new
    tpl = OpsCheckTemplate.find_by(id: params[:template_id], project_id: @project.id)
    today = User.current.today
    @check = OpsCheck.new(project: @project, ops_check_template: tpl, checked_on: today, user: User.current,
                          name: tpl ? "#{today.strftime('%Y년 %-m월')} #{tpl.name}" : '')
    @check.result_list = (tpl&.item_list || []).map { |i| { 'item' => i, 'result' => 'ok', 'action' => '' } }
  end

  def create
    @check = OpsCheck.new(project: @project)
    assign
    if @check.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to project_ops_check_path(@project, @check)
    else
      render :new
    end
  end

  def edit
  end

  def update
    assign
    if @check.save
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_ops_check_path(@project, @check)
    else
      render :edit
    end
  end

  def destroy
    @check.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_ops_checks_path(@project)
  end

  private

  def find_check
    @check = OpsCheck.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  # items[n][item|result|action] (항목 이름이 빈 줄은 버림)
  def assign
    p = params.require(:ops_check).permit(:name, :checked_on, :note, :ops_check_template_id)
    @check.assign_attributes(p.except(:ops_check_template_id))
    tpl = OpsCheckTemplate.find_by(id: p[:ops_check_template_id], project_id: @project.id)
    @check.ops_check_template = tpl if p.key?(:ops_check_template_id)
    @check.user ||= User.current
    raw = params[:items].respond_to?(:to_unsafe_h) ? params[:items].to_unsafe_h.values : []
    @check.result_list = raw.filter_map do |r|
      item = r['item'].to_s.strip
      next if item.empty?
      { 'item' => item.truncate(200), 'result' => r['result'].to_s.presence_in(OpsCheck::RESULTS) || 'ok', 'action' => r['action'].to_s.strip.truncate(1000) }
    end
  end
end
