# 프로젝트 > 시스템 권한 — 개발 대상 시스템의 권한 등급, 메뉴 × 권한 매트릭스(조회/편집/전체), 엑셀 내보내기
class SysRolesController < ApplicationController
  menu_item :sys_roles
  helper :menu_items

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_role, only: [:edit, :update, :destroy]

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
    menu_ids = MenuItem.where(project_id: @project.id).pluck(:id)
    role_ids = SysRole.where(project_id: @project.id).pluck(:id)
    input = params[:a].respond_to?(:to_unsafe_h) ? params[:a].to_unsafe_h : (params[:a] || {})
    MenuRoleAccess.transaction do
      input.each do |mid, by_role|
        mid = mid.to_i
        next unless menu_ids.include?(mid) && by_role.respond_to?(:each)
        by_role.each do |rid, access|
          rid = rid.to_i
          next unless role_ids.include?(rid)
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

  def export
    load_matrix
    max = (@ordered.map(&:last).max || 0) + 1
    header = (1..max).map { |d| "#{d}뎁스" } + ['화면 ID', 'URL'] + @roles.map { |r| r.code ? "#{r.name}(#{r.code})" : r.name }
    rows = @ordered.map do |m, d|
      Array.new(d) + [m.name] + Array.new(max - d - 1) + [m.screen_id, m.url] +
        @roles.map { |r| MenuRoleAccess::CODES[@cells[[m.id, r.id]]] }
    end
    legend = [['R', l(:label_sys_access_read)], ['CRU', l(:label_sys_access_write)], ['CRUD', l(:label_sys_access_full)]]
    roles = @roles.map { |r| [r.level, r.name, r.code, r.description, r.active? ? 'Y' : 'N'] }
    data = KrdsUi::Xlsx.build([
      { name: '메뉴 권한', header: header, rows: rows, widths: Array.new(max, 18) + [16, 28] + @roles.map { 12 } },
      { name: '권한 등급', header: %w(등급 이름 코드 설명 사용), rows: roles, widths: [8, 20, 14, 50, 6] },
      { name: '표기', header: %w(표기 의미), rows: legend, widths: [10, 40] }
    ])
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
    params.require(:sys_role).permit(:name, :code, :level, :description, :active)
  end

  def load_matrix
    @roles = SysRole.where(project_id: @project.id).active.sorted.to_a
    @ordered = @project.module_enabled?(:menu_tree) ? MenuItem.ordered(@project) : []
    @cells = MenuRoleAccess.where(menu_item_id: @ordered.map { |m, _| m.id }, sys_role_id: @roles.map(&:id))
                           .pluck(:menu_item_id, :sys_role_id, :access).to_h { |m, r, a| [[m, r], a] }
  end
end
