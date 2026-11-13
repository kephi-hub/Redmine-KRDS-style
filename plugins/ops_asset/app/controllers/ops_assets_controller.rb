# 프로젝트 > 자산 — 프로젝트 자산 + 연결된 공용 자산, 만료 KPI·필터, 등록·수정(프로젝트 자산), 공용 자산 연결·해제, 엑셀
class OpsAssetsController < ApplicationController
  menu_item :ops_assets
  helper :ops_asset
  include OpsAssetHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_asset, only: [:edit, :update, :destroy]
  before_action :find_visible_asset, only: [:collect, :cert]

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
    @kpi[:disk] = all.count(&:disk_warn?)
    @state = 'disk' if params[:state] == 'disk'
    list = list.select(&:disk_warn?) if @state == 'disk'
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

  # 서버 정보 수집 (SSH) — 연결한 SSH 접속정보로 접속할 권한도 있어야 함
  def collect
    key = @asset.vault_key
    unless key && defined?(SshConsole::Access) && SshConsole::Access.can_connect?(User.current, key)
      flash[:error] = l(:error_oa_no_ssh_key)
      return redirect_to(project_ops_assets_path(@project))
    end
    r = OpsKit::Probe.server(@asset, user: User.current)
    if r[:ok] then flash[:notice] = l(:notice_oa_collected, name: @asset.name, summary: OpsKit::Probe.summary(r[:info]))
    else flash[:error] = l(:error_oa_collect, name: @asset.name, msg: r[:error]) end
    redirect_to project_ops_assets_path(@project)
  end

  # HTTPS 인증서 확인 (SSH 없이 443)
  def cert
    r = OpsKit::Probe.cert(@asset)
    if r[:ok] then flash[:notice] = l(:notice_oa_cert, name: @asset.name, date: r[:info][:not_after], subject: r[:info][:subject])
    else flash[:error] = l(:error_oa_cert, name: @asset.name, msg: r[:error]) end
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
    p = params.require(:ops_asset).permit(:kind, :name, :env, :address, :spec, :vendor, :owner, :expires_on, :renew_cycle, :db_server_id, :jenkins_server_id, :note, :active, :vault_key_id)
    p[:vault_key_id] = nil unless ssh_keys.any? { |k| k.id == p[:vault_key_id].to_i }
    p
  end

  # 이 프로젝트에서 그 사용자가 볼 수 있는 "SSH 서버" 접속정보
  def ssh_keys
    return [] unless defined?(SshConsole::Access) && @project.module_enabled?(:keys)
    @ssh_keys ||= SshConsole::Access.visible_keys(User.current, @project).select { |k| SshConsole::Target.ssh_key?(k) }
  end
  helper_method :ssh_keys

  def find_visible_asset
    @asset = OpsAsset.for_project(@project).find_by!(id: params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end
end
