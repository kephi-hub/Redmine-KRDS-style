# 프로젝트 > 시스템 권한 — 개발 대상 시스템의 권한 등급, 메뉴 × 권한 매트릭스(조회/편집/전체), 엑셀 내보내기
class SysRolesController < ApplicationController
  menu_item :sys_roles
  helper :menu_items
  include MenuTree::SiteScope

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_role, only: [:edit, :update, :destroy]
  before_action -> { @sites = MenuSite.where(project_id: @project.id).sorted.to_a }, only: [:index, :new, :create, :edit, :update]
  before_action -> { load_sites(allow_all: true) }, only: [:matrix]

  def index
    @roles = SysRole.where(project_id: @project.id).sorted.to_a
    @counts = MenuRoleAccess.where(sys_role_id: @roles.map(&:id)).group(:sys_role_id).count
  end

  def new
    @role = SysRole.new(project: @project, level: (SysRole.where(project_id: @project.id).maximum(:level) || 0) + 10)
  end

  def create
    @role = SysRole.new(role_params.merge(project: @project, position: (SysRole.where(project_id: @project.id).maximum(:position) || 0) + 1))
    if @role.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to project_sys_roles_path(@project)
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @role.update(role_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_sys_roles_path(@project)
    else
      render :edit
    end
  end

  def destroy
    @role.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_sys_roles_path(@project)
  end

  # 메뉴 × 권한 매트릭스 (메뉴 구조도 모듈의 메뉴 사용)
  def matrix
    load_matrix
  end

  # a[메뉴 id][권한 id] = '' | read | write | full — 보낸 메뉴·권한 범위만 바꿈
  def save_matrix
    menus = MenuItem.where(project_id: @project.id).index_by(&:id)
    roles = SysRole.where(project_id: @project.id).index_by(&:id)
    input = params[:a].respond_to?(:to_unsafe_h) ? params[:a].to_unsafe_h : (params[:a] || {})
    MenuRoleAccess.transaction do
      input.each do |mid, by_role|
        mid = mid.to_i
        next unless menus[mid] && by_role.respond_to?(:each)
        by_role.each do |rid, access|
          rid = rid.to_i
          # 다른 사이트 전용 등급은 이 메뉴에 저장하지 않음
          next unless roles[rid]&.applies_to?(menus[mid])
          rec = MenuRoleAccess.find_by(menu_item_id: mid, sys_role_id: rid)
          if MenuRoleAccess::LEVELS.include?(access)
            rec ? rec.update!(access: access) : MenuRoleAccess.create!(menu_item_id: mid, sys_role_id: rid, access: access)
          else
            rec&.delete
          end
        end
      end
    end
    flash[:notice] = l(:notice_successful_update)
    redirect_to project_sys_roles_matrix_path(@project)
  end

  # 엑셀은 모든 사이트 · 모든 등급 (다른 사이트 전용 칸은 ·)
  def export
    @site = nil
    load_matrix
    data = MenuTree::Sheet.roles_book(@project, @ordered, @roles, @cells)
    send_data data, filename: "메뉴권한_#{@project.identifier}_#{User.current.today.strftime('%Y%m%d')}.xlsx",
                    type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  end

  private

  def find_role
    @role = SysRole.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def role_params
    params.require(:sys_role).permit(:name, :code, :level, :description, :active, :menu_site_id)
  end

  # 사이트를 고르면 그 사이트 메뉴와, 그 사이트에 쓰는 등급(적용 사이트가 비었거나 같은 것)만
  def load_matrix
    @roles = SysRole.where(project_id: @project.id).active.sorted.to_a
    @roles = @roles.select { |r| r.menu_site_id.nil? || r.menu_site_id == @site.id } if @site
    @ordered = @project.module_enabled?(:menu_tree) ? MenuItem.ordered(@project, site: @site&.id) : []
    @cells = MenuRoleAccess.where(menu_item_id: @ordered.map { |m, _| m.id }, sys_role_id: @roles.map(&:id))
                           .pluck(:menu_item_id, :sys_role_id, :access).to_h { |m, r, a| [[m, r], a] }
  end
end
