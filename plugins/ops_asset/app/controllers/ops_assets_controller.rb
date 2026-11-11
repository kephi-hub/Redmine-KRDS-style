# 프로젝트 > 자산 — 프로젝트 자산 + 연결된 공용 자산, 만료 KPI·필터, 등록·수정(프로젝트 자산), 공용 자산 연결·해제, 엑셀
class OpsAssetsController < ApplicationController
  menu_item :ops_assets
  helper :ops_asset
  include OpsAssetHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_asset, only: [:edit, :update, :destroy]

  def index
    all = OpsAsset.for_project(@project).sorted.to_a
    @kpi = asset_kpi(all)
    @kind = params[:kind].presence_in(OpsAsset::KINDS)
    @state = params[:state].presence_in(%w(expired soon7 soon30))
    @q = params[:q].to_s.strip
    list = all
    list = list.select { |a| a.kind == @kind } if @kind
    list = list.select { |a| @state == 'soon30' ? %i(soon7 soon30).include?(a.expiry_state) : a.expiry_state.to_s == @state } if @state
    list = list.select { |a| [a.name, a.address, a.owner, a.vendor, a.note].compact.any? { |v| v.downcase.include?(@q.downcase) } } if @q.present?
    @assets = list
    @linkable = User.current.allowed_to?(:manage_ops_assets, @project) ? OpsAsset.where(project_id: nil, active: true).where.not(id: all.map(&:id)).sorted.to_a : []
  end

  def new
    @asset = OpsAsset.new(project: @project, kind: params[:kind].presence_in(OpsAsset::KINDS) || 'server')
  end

  def create
    @asset = OpsAsset.new(asset_params.merge(project: @project, author_id: User.current.id))
    if @asset.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to project_ops_assets_path(@project)
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @asset.update(asset_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_ops_assets_path(@project)
    else
      render :edit
    end
  end

  def destroy
    @asset.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_ops_assets_path(@project)
  end

  # 공용 자산 연결·해제
  def link
    asset = OpsAsset.find_by(id: params[:asset_id], project_id: nil)
    return render_404 unless asset
    OpsAssetLink.find_or_create_by!(ops_asset_id: asset.id, project_id: @project.id)
    flash[:notice] = l(:notice_ops_asset_linked, name: asset.name)
    redirect_to project_ops_assets_path(@project)
  end

  def unlink
    OpsAssetLink.where(ops_asset_id: params[:id], project_id: @project.id).delete_all
    flash[:notice] = l(:notice_ops_asset_unlinked)
    redirect_to project_ops_assets_path(@project)
  end

  def export
    send_data OpsKit::Sheet.assets(OpsAsset.for_project(@project).sorted.to_a, @project),
              filename: "자산대장_#{@project.identifier}_#{User.current.today.strftime('%Y%m%d')}.xlsx", type: OpsKit::Sheet::XLSX
  end

  private

  # 프로젝트 자산만 고칠 수 있음 (공용 자산은 관리자 화면)
  def find_asset
    @asset = OpsAsset.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def asset_params
    params.require(:ops_asset).permit(:kind, :name, :env, :address, :spec, :vendor, :owner, :expires_on, :renew_cycle, :db_server_id, :jenkins_server_id, :note, :active)
  end
end
