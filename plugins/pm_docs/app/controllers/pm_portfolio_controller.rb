# 전체 프로젝트 현황 (PMO) — 볼 수 있는 진행 중 프로젝트마다 한 줄(신호등 · 진척 대비 경과 · 일감 · 요구사항 · 프로그램 · 테스트 ·
# 위험 · 산출물 · 변경요청 · SR · 감리 · 투입), 엑셀. 칸마다 그 사용자의 프로젝트 권한을 따름
class PmPortfolioController < ApplicationController
  menu_item :pm_portfolio
  helper :pm_docs
  include PmDocsHelper

  before_action :require_login

  def index
    @rows = PmKit::Portfolio.rows
    @all = @rows
    @signal = params[:signal].presence_in(%w(red yellow green))
    @rows = @rows.select { |m| m[:signal] == @signal } if @signal
    @q = params[:q].to_s.strip
    @rows = @rows.select { |m| m[:project].name.downcase.include?(@q.downcase) } if @q.present?
    order = { 'red' => 0, 'yellow' => 1, 'green' => 2 }
    @rows = @rows.sort_by { |m| [order[m[:signal]], m[:project].lft || 0] }
  end

  def export
    send_data PmKit::Portfolio.sheet(PmKit::Portfolio.rows), filename: "프로젝트현황_#{User.current.today.strftime('%Y%m%d')}.xlsx", type: PmKit::Sheet::XLSX
  end
end
