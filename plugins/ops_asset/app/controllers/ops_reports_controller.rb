# 프로젝트 > 점검·장애 > 월간 보고서 — 달을 골라 미리보기, 엑셀(요약·장애·정기점검·일감·배포·DB 구조 변경·만료 예정 자산)
class OpsReportsController < ApplicationController
  menu_item :ops_incidents
  helper :ops_asset
  include OpsAssetHelper

  before_action :find_project_by_project_id
  before_action :authorize

  def index
    @month = (Date.strptime(params[:month].to_s, '%Y-%m') rescue User.current.today.beginning_of_month)
    @report = OpsKit::Report.build(@project, @month)
    return unless params[:download] == 'xlsx'
    send_data OpsKit::Report.xlsx(@report), filename: "월간운영보고서_#{@project.identifier}_#{@month.strftime('%Y%m')}.xlsx", type: OpsKit::Sheet::XLSX
  end
end
