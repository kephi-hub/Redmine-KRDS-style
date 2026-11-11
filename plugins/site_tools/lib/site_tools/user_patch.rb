# 사용자 저장 후 같은 로그인 ID 의 미연결 커미터를 연결
module SiteTools
  module UserPatch
    def self.prepended(base)
      base.after_commit :site_tools_map_committers, on: [:create, :update]
    end

    private

    def site_tools_map_committers
      return unless saved_change_to_login? || previous_changes.key?('id') || saved_change_to_status?
      SiteTools::Committers.map_user(self) if active?
    end
  end
end
