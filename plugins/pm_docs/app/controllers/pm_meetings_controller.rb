# 프로젝트 > 회의록 — 일시·장소·참석자·안건·내용·결정 사항·후속 조치(일감 자동 생성)
class PmMeetingsController < ApplicationController
  menu_item :meetings
  helper :pm_docs
  include PmDocsHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_meeting, only: [:show, :edit, :update, :destroy]

  def index
    @meetings = PmMeeting.where(project_id: @project.id).sorted.to_a
    @open_actions = @meetings.sum { |m| m.action_list.count { |a| a['issue_id'] && (i = Issue.find_by(id: a['issue_id'])) && !i.closed? } }
  end

  def show
    @issues = Issue.where(id: @meeting.action_list.map { |a| a['issue_id'] }.compact).includes(:status, :assigned_to).index_by(&:id)
  end

  def new
    z = ActiveSupport::TimeZone['Asia/Seoul']
    @meeting = PmMeeting.new(project: @project, held_at: z.now.change(min: 0), title: '')
    load_form
  end

  def create
    @meeting = PmMeeting.new(project: @project, author: User.current)
    assign
    if @meeting.save
      created = create_issues
      flash[:notice] = created.positive? ? l(:notice_pm_meeting_issues, count: created) : l(:notice_successful_create)
      redirect_to project_pm_meeting_path(@project, @meeting)
    else
      load_form
      render :new
    end
  end

  def edit
    load_form
  end

  def update
    assign
    if @meeting.save
      created = create_issues
      flash[:notice] = created.positive? ? l(:notice_pm_meeting_issues, count: created) : l(:notice_successful_update)
      redirect_to project_pm_meeting_path(@project, @meeting)
    else
      load_form
      render :edit
    end
  end

  def destroy
    @meeting.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to project_pm_meetings_path(@project)
  end

  private

  def find_meeting
    @meeting = PmMeeting.find_by!(id: params[:id], project_id: @project.id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def load_form
    @members = pm_members(@project)
    @trackers = @project.trackers.to_a
  end

  # decisions[] (빈 줄 버림), actions[n][title|assignee_id|due_on|issue_id|make]
  def assign
    p = params.require(:pm_meeting).permit(:title, :held_at, :place, :attendees, :agenda, :notes)
    p[:held_at] = (ActiveSupport::TimeZone['Asia/Seoul'].parse(p[:held_at]) rescue nil) if p.key?(:held_at)
    @meeting.assign_attributes(p)
    @meeting.decisions = Array(params[:decisions]).map { |d| d.to_s.strip.truncate(500) }.reject(&:empty?).to_json
    raw = params[:actions].respond_to?(:to_unsafe_h) ? params[:actions].to_unsafe_h.values : []
    member_ids = @project.users.pluck(:id)
    @make = []
    list = raw.filter_map do |a|
      title = a['title'].to_s.strip
      next if title.empty?
      item = { 'title' => title.truncate(200), 'assignee_id' => (member_ids.include?(a['assignee_id'].to_i) ? a['assignee_id'].to_i : nil),
               'due_on' => (Date.parse(a['due_on']).to_s rescue nil), 'issue_id' => a['issue_id'].presence&.to_i }
      @make << item if a['make'] == '1' && item['issue_id'].nil?
      item
    end
    @meeting.actions = list.to_json
  end

  # 후속 조치 → 일감 (고른 것만, 트래커는 고른 것 · 기본 "작업")
  def create_issues
    return 0 if @make.blank? || !User.current.allowed_to?(:add_issues, @project)
    tracker = @project.trackers.find_by(id: params[:tracker_id]) || @project.trackers.find_by(name: '작업') || @project.trackers.first
    list = @meeting.action_list
    n = 0
    @make.each do |item|
      i = list.index { |x| x['title'] == item['title'] && x['issue_id'].nil? }
      next unless i
      issue = Issue.new(project: @project, author: User.current, tracker: tracker)
      issue.status = tracker&.default_status
      issue.priority = IssuePriority.default || IssuePriority.active.first
      issue.subject = item['title']
      issue.description = "회의: #{@meeting.title} (#{pm_time(@meeting.held_at)})"
      issue.assigned_to = @project.users.find_by(id: item['assignee_id'])
      issue.due_date = item['due_on'].present? ? Date.parse(item['due_on']) : nil
      next unless issue.save
      list[i]['issue_id'] = issue.id
      n += 1
    end
    @meeting.update_column(:actions, list.to_json) if n.positive?
    n
  end
end
