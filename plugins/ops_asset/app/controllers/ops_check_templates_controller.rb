# 점검표 양식 — 이름과 항목(한 줄에 하나)
class OpsCheckTemplatesController < ApplicationController
  menu_item :ops_incidents
  helper :ops_asset
  include OpsAssetHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_template, only: [:edit, :update, :destroy]

  def new
    @template = OpsCheckTemplate.new(project: @project, name: l(:label_oa_tpl_default_name), items: l(:text_oa_tpl_default_items))
  end

  def create
    @template = OpsCheckTemplate.new(template_params.merge(project: @project))
    if @template.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to project_ops_checks_path(@project)
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @template.update(template_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to project_ops_checks_path(@project)
    else
      render :edit
    end
  end

  def destroy
    OpsCheck.where(ops_check_template_id: @template.id).update_all(ops_check_template_id: nil)
    @template.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_ops_checks_path(@project)
  end

  private

  def find_template
    @template = OpsCheckTemplate.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def template_params
    params.require(:ops_check_template).permit(:name, :items)
  end
end
