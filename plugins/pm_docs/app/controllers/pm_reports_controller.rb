# 프로젝트 > 보고서 — 주간·월간 보고서 미리보기와 엑셀 (PmKit::Report)
class PmReportsController < ApplicationController
  menu_item :pm_reports
  helper :pm_docs
  include PmDocsHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :load_period

  def index
    @data = PmKit::Report.build(@project, @from, @to)
  end

  def export
    data = PmKit::Report.build(@project, @from, @to)
    name = @kind.to_s.include?('month') ? '월간보고서' : '주간보고서'
    send_data PmKit::Sheet.report(@project, data, params[:notes].to_s.strip.truncate(4000)),
              filename: "#{name}_#{@project.identifier}_#{@from.strftime('%Y%m%d')}-#{@to.strftime('%Y%m%d')}.xlsx", type: PmKit::Sheet::XLSX
  end

  private

  def load_period
    @kind = params[:kind].presence_in(%w(week last_week month last_month custom)) || 'week'
    if @kind == 'custom'
      @from = (Date.parse(params[:from]) rescue nil)
      @to = (Date.parse(params[:to]) rescue nil)
      @from, @to = PmKit::Report.period('week') unless @from && @to && @from <= @to && (@to - @from) <= 366
    else
      @from, @to = PmKit::Report.period(@kind)
    end
  end
end
