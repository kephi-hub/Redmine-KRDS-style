# 관리 > 자산 대장 — 모든 자산(공용·프로젝트), 공용 자산 등록·수정·삭제, 연결된 프로젝트, 엑셀, 메일 알림 대상 미리보기
class AdminOpsAssetsController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :admin_ops_assets
  helper :ops_asset
  include OpsAssetHelper

  before_action :require_admin
  before_action :find_asset, only: [:edit, :update, :destroy]

  def index
    all = OpsAsset.includes(:project, :linked_projects).sorted.to_a
    @kpi = asset_kpi(all)
    @scope = params[:scope].presence_in(%w(shared project))
    @state = params[:state].presence_in(%w(expired soon7 soon30))
    list = all
    list = list.select { |a| @scope == 'shared' ? a.shared? : !a.shared? } if @scope
    list = list.select { |a| @state == 'soon30' ? %i(soon7 soon30).include?(a.expiry_state) : a.expiry_state.to_s == @state } if @state
    @assets = list
    @due = OpsKit::Notifier.due
    return unless params[:download] == 'xlsx'
    send_data OpsKit::Sheet.assets(all), filename: "자산대장_전체_#{User.current.today.strftime('%Y%m%d')}.xlsx", type: OpsKit::Sheet::XLSX
  end

  def new
    @asset = OpsAsset.new(kind: 'server')
  end

  def create
    @asset = OpsAsset.new(asset_params.merge(author_id: User.current.id))
    if @asset.save
      save_links
      flash[:notice] = l(:notice_successful_create)
      redirect_to admin_ops_assets_path
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @asset.update(asset_params)
      save_links
      flash[:notice] = l(:notice_successful_update)
      redirect_to admin_ops_assets_path
    else
      render :edit
    end
  end

  def destroy
    @asset.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to admin_ops_assets_path
  end

  private

  def find_asset
    @asset = OpsAsset.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def asset_params
    params.require(:ops_asset).permit(:kind, :name, :env, :address, :spec, :vendor, :owner, :expires_on, :renew_cycle, :db_server_id, :jenkins_server_id, :note, :active)
  end

  # 공용 자산만: 연결 프로젝트 (보낸 경우만)
  def save_links
    return unless @asset.shared? && params[:links_sent] == '1'
    @asset.linked_project_ids = Array(params[:project_ids]).map(&:to_i) & Project.active.pluck(:id)
  end
end
