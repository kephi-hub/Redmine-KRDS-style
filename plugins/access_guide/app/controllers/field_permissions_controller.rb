# 관리 > 항목 편집 권한 설정 — 역할마다 "상태 × 항목" 표 하나(편집·읽기 전용·필수)를 여러 일감 유형에 한 번에 적용
# 저장은 Redmine 원본 WorkflowPermission.replace_permissions 를 그대로 씀. 유형마다 값이 달라 "섞임" 인 칸은 건드리지 않으면 그대로 둠
class FieldPermissionsController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :field_permissions
  helper :access_overview
  before_action :require_admin
  before_action :load_common

  # 항상 입력해야 하는 항목은 "필수" 를 고를 수 없음 (원본 field_required? 와 같은 기준)
  ALWAYS_REQUIRED = %w(project_id tracker_id subject priority_id is_private).freeze

  def index
    @role = @roles.find { |r| r.id == params[:role_id].to_i } || @roles.first
    return unless @role
    rules = WorkflowPermission.where(role_id: @role.id, tracker_id: @trackers.map(&:id)).pluck(:tracker_id, :old_status_id, :field_name, :rule)
    by_cell = Hash.new { |h, k| h[k] = {} }
    rules.each { |t, s, f, r| by_cell[[s, f]][t] = r }
    # 칸 값: 모든 유형이 같으면 그 값('' = 편집 가능), 다르면 'mixed'
    @cells = {}
    @statuses.each do |st|
      @fields.each do |key, _|
        vals = @trackers.map { |t| by_cell[[st.id, key]][t.id].to_s }.uniq
        @cells[[st.id, key]] = vals.size == 1 ? vals.first : 'mixed'
      end
    end
    @rule_count = rules.group_by(&:first).transform_values(&:size)
  end

  def update
    role = @roles.find { |r| r.id == params[:role_id].to_i } or return render_404
    trackers = @trackers.select { |t| Array(params[:tracker_ids]).map(&:to_i).include?(t.id) }
    if trackers.empty?
      flash[:error] = l(:error_simple_workflow_no_tracker)
      return redirect_to field_permissions_path(role_id: role.id)
    end
    keys = @fields.map(&:first)
    status_ids = @statuses.map(&:id)
    input = params[:p].respond_to?(:to_unsafe_h) ? params[:p].to_unsafe_h : {}
    permissions = {}
    input.each do |status_id, by_field|
      next unless status_ids.include?(status_id.to_i) && by_field.is_a?(Hash)
      by_field.each do |field, rule|
        next unless keys.include?(field) && %w(none readonly required).include?(rule) # mixed 는 그대로
        next if rule == 'required' && always_required?(field)
        (permissions[status_id.to_s] ||= {})[field] = rule == 'none' ? '' : rule
      end
    end
    WorkflowPermission.replace_permissions(trackers, [role], permissions)
    changed = permissions.values.sum(&:size)
    flash[:notice] = l(:notice_field_permissions_saved, role: role.name, count: trackers.size, cells: changed)
    redirect_to field_permissions_path(role_id: role.id)
  end

  private

  def load_common
    @roles = Role.givable.sorted.to_a
    @trackers = Tracker.sorted.to_a
    @statuses = IssueStatus.sorted.to_a
    disabled_everywhere = @trackers.map(&:disabled_core_fields).reduce(:&) || []
    @fields = (Tracker::CORE_FIELDS_ALL - disabled_everywhere).map { |f| [f, l("field_#{f.delete_suffix('_id')}")] }
    @custom_fields = @trackers.flat_map(&:custom_fields).uniq.sort
    @fields += @custom_fields.map { |cf| [cf.id.to_s, cf.name, cf] }
  end

  def always_required?(field)
    return ALWAYS_REQUIRED.include?(field) unless field.match?(/\A\d+\z/)
    cf = @custom_fields.find { |c| c.id.to_s == field }
    cf.nil? || cf.is_required?
  end
  helper_method :always_required?
end
