# 프로젝트 > 인터페이스 — 연계 목록, 구성도(Mermaid, 우리 시스템 가운데), 등록·수정, 인터페이스 정의서 엑셀
class OpsInterfacesController < ApplicationController
  menu_item :ops_interfaces
  helper :ops_asset
  include OpsAssetHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_interface, only: [:show, :edit, :update, :destroy]

  def index
    all = OpsInterface.where(project_id: @project.id).includes(:ops_schedule).sorted.to_a
    @kpi = { all: all.size, partners: all.map(&:partner).uniq.size, send: all.count { |i| i.direction != 'recv' }, recv: all.count { |i| i.direction != 'send' },
             realtime: all.count { |i| i.cycle == 'realtime' } }
    @partner = params[:partner].presence
    @q = params[:q].to_s.strip
    list = all
    list = list.select { |i| i.partner == @partner } if @partner
    list = list.select { |i| [i.code, i.name, i.partner, i.data_desc, i.tables].compact.any? { |v| v.downcase.include?(@q.downcase) } } if @q.present?
    @interfaces = list
    @partners = all.map(&:partner).uniq.sort
  end

  # 구성도: download=md|mmd|drawio
  def diagram
    list = OpsInterface.where(project_id: @project.id).where.not(status: 'stopped').sorted.to_a
    @mermaid = OpsKit::Diagram.mermaid(@project.name, list)
    base = "연계구성도_#{@project.identifier}_#{User.current.today.strftime('%Y%m%d')}"
    case params[:download]
    when 'mmd' then send_data @mermaid, filename: "#{base}.mmd", type: 'text/plain; charset=utf-8'
    when 'md' then send_data "# #{@project.name} 연계 구성도\n\n```mermaid\n#{@mermaid}\n```\n", filename: "#{base}.md", type: 'text/markdown; charset=utf-8'
    when 'drawio' then send_data OpsKit::Diagram.drawio(@project.name, list), filename: "#{base}.drawio", type: 'application/xml; charset=utf-8'
    end
    @count = list.size
  end

  def show
  end

  def new
    @interface = OpsInterface.new(project: @project, direction: 'send', protocol: 'rest', cycle: 'realtime', status: 'active')
  end

  def create
    @interface = OpsInterface.new(interface_params.merge(project: @project, author_id: User.current.id))
    if @interface.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to params[:continue] ? new_project_ops_interface_path(@project) : project_ops_interface_path(@project, @interface)
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @interface.update(interface_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_ops_interface_path(@project, @interface)
    else
      render :edit
    end
  end

  def destroy
    @interface.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_ops_interfaces_path(@project)
  end

  def export
    send_data OpsKit::Sheet.interfaces(OpsInterface.where(project_id: @project.id).includes(:ops_schedule).sorted.to_a),
              filename: "인터페이스정의서_#{@project.identifier}_#{User.current.today.strftime('%Y%m%d')}.xlsx", type: OpsKit::Sheet::XLSX
  end

  private

  def find_interface
    @interface = OpsInterface.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def interface_params
    p = params.require(:ops_interface).permit(:code, :name, :direction, :partner, :protocol, :cycle, :ops_schedule_id, :data_desc, :tables, :dev_url, :prod_url,
                                              :our_owner, :partner_owner, :partner_contact, :auth_note, :status, :note)
    p[:ops_schedule_id] = nil unless OpsSchedule.exists?(id: p[:ops_schedule_id], project_id: @project.id)
    p
  end
end
