# 프로젝트 > DB — 테이블 목록·컬럼 상세, 테이블 정의서(엑셀), 개발/운영 비교, 용어사전 점검
# 원격 DB 에는 읽기 전용 세션으로 메타데이터만 조회
require 'csv'
class DbSchemasController < ApplicationController
  menu_item :db_schemas
  helper :db_schemas

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :load_links
  before_action :find_link, only: [:table, :export, :check]

  def index
    @link = @links.find { |l| l.id.to_s == params[:link].to_s } || @links.first
    return unless @link
    @snapshot = snapshot(@link)
    @terms = DbManage::Analysis.term_map(@project)
  end

  def table
    @snapshot = snapshot(@link)
    return unless @snapshot
    @table = @snapshot[:tables].find { |t| t[:name] == params[:table] }
    return render_404 unless @table
    @columns = @snapshot[:columns][@table[:name]] || []
    @terms = DbManage::Analysis.term_map(@project)
  end

  # 테이블 정의서 — 시트 1: 테이블 목록, 시트 2: 컬럼 정의
  def export
    snap = snapshot(@link)
    return redirect_to(project_db_schemas_path(@project, link: @link.id)) unless snap
    terms = DbManage::Analysis.term_map(@project)
    tables = snap[:tables].each_with_index.map do |t, i|
      [i + 1, t[:name], t[:view] ? '뷰' : '테이블', t[:comment], (snap[:columns][t[:name]] || []).size, t[:view] ? nil : t[:rows]]
    end
    columns = []
    snap[:tables].each do |t|
      (snap[:columns][t[:name]] || []).each do |c|
        term = terms && DbManage::Analysis.term_status(c, terms).last
        columns << [t[:name], t[:comment], c[:position], c[:name], c[:type], c[:nullable] ? 'Y' : 'N', c[:default], c[:keys].join(', '), c[:ref], c[:comment], term&.name]
      end
    end
    sheets = [
      { name: '테이블 목록', header: %w(No 테이블명 구분 설명 컬럼\ 수 행\ 수(추정)), rows: tables, widths: [6, 30, 8, 40, 10, 14] },
      { name: '컬럼 정의', header: %w(테이블명 테이블\ 설명 No 컬럼명 데이터\ 타입 Null 기본값 키 참조 설명 용어), rows: columns,
        widths: [26, 24, 6, 26, 20, 6, 18, 10, 24, 36, 18] }
    ]
    name = "테이블정의서_#{@project.identifier}_#{@link.name}_#{User.current.today.strftime('%Y%m%d')}.xlsx"
    send_data DbManage::Xlsx.build(sheets), filename: name,
              type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
  end

  # 두 DB(기본: 운영 아님 ↔ 운영) 의 테이블·컬럼 차이
  def compare
    return if @links.size < 2
    @a = @links.find { |l| l.id.to_s == params[:a].to_s } || @links.find { |l| !l.production? } || @links.first
    @b = @links.find { |l| l.id.to_s == params[:b].to_s } || (@links - [@a]).find(&:production?) || (@links - [@a]).first
    return if @a == @b
    sa = snapshot(@a); sb = sa && snapshot(@b)
    @result = DbManage::Analysis.compare(sa, sb) if sa && sb
  end

  # 컬럼명(중복 제거)을 용어사전 약어와 대조. format=csv 는 미등록 컬럼을 용어사전 가져오기 양식으로
  def check
    @terms = DbManage::Analysis.term_map(@project)
    return unless @terms
    snap = snapshot(@link)
    return unless snap
    rows = {}
    snap[:tables].each do |t|
      (snap[:columns][t[:name]] || []).each do |c|
        r = rows[c[:name].upcase] ||= { name: c[:name], tables: [], comments: [], types: [], column: c }
        r[:tables] << t[:name]
        r[:comments] |= [c[:comment]].compact
        r[:types] |= [c[:type]]
      end
    end
    rows.each_value { |r| r[:status], r[:term] = DbManage::Analysis.term_status(r[:column], @terms) }
    @rows = rows.values.sort_by { |r| [%i(type missing ok).index(r[:status]), r[:name]] }
    @counts = @rows.group_by { |r| r[:status] }.transform_values(&:size)
    @status = %w(ok type missing).include?(params[:status]) ? params[:status].to_sym : nil
    if params[:format] == 'csv'
      data = CSV.generate do |csv|
        csv << %w(용어 영문명 약어 분류 데이터타입 길이 정의 비고)
        @rows.select { |r| r[:status] == :missing }.each do |r|
          base, len = DbManage::Analysis.split_type(r[:types].first)
          csv << [r[:comments].first.presence || r[:name], nil, r[:name].upcase, nil, base.upcase, len.presence, nil, "사용 테이블: #{r[:tables].first(5).join(', ')}"]
        end
      end
      return send_data("﻿" + data, type: 'text/csv; charset=utf-8',
                       filename: "미등록컬럼_#{@project.identifier}_#{@link.name}_#{User.current.today.strftime('%Y%m%d')}.csv")
    end
    @shown = @status ? @rows.select { |r| r[:status] == @status } : @rows
  end

  private

  def load_links
    @links = @project.db_links.includes(:db_server).sorted.to_a
  end

  def find_link
    @link = @links.find { |l| l.id.to_s == params[:link_id].to_s }
    render_404 unless @link
  end

  # 접속 실패는 화면에 메시지로 보여 주고 nil
  def snapshot(link)
    link.connector.snapshot
  rescue DbManage::Error => e
    @db_error = "#{link.name}: #{e.message}"
    nil
  end
end
