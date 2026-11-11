# 관리 > 역할 및 권한 > 권한 설정 (원본 권한 보고서 + 권한 한눈에 보기를 한 화면으로)
# - 권한 화면에 업무흐름·사용자 역할표 데이터를 더함
# - 저장 후 역할 목록 대신 같은 화면으로 돌아옴 (보던 역할 필터 유지)
module AccessGuide
  module RolesPatch
    def permissions
      @givable_roles = Role.givable.sorted.to_a
      @closed_ids = IssueStatus.where(is_closed: true).pluck(:id)
      trackers = Tracker.sorted.to_a
      @missing = @givable_roles.to_h do |r|
        have = WorkflowTransition.where(role_id: r.id).distinct.pluck(:tracker_id)
        [r.id, trackers.reject { |t| have.include?(t.id) }]
      end
      @projects = Project.active.sorted.to_a
      @users = User.active.sorted.to_a
      @memberships = Member.joins(:project).merge(Project.active).includes(:roles, :principal, :project).to_a.group_by(&:user_id)
      super
    end

    def update_permissions
      (params[:permissions] || {}).each do |role_id, perms|
        role = Role.find_by(id: role_id)
        next unless role
        role.permissions = perms
        role.save
      end
      flash[:notice] = l(:notice_successful_update)
      ids = Array(params[:ids]).reject(&:blank?)
      redirect_to permissions_roles_path(ids.any? ? { ids: ids } : {})
    end
  end
end
