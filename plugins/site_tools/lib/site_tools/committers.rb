# 저장소 커미터 ↔ Redmine 사용자 자동 연결 — 커미터 이름이 지금 사용자의 로그인 ID(대소문자 무시) 또는 메일과 같으면 연결
# 기본은 아직 연결 안 된 커미터만 (화면에서 직접 고른 연결은 건드리지 않음)
module SiteTools
  module Committers
    module_function

    def user_index
      users = User.where(type: 'User').where.not(status: User::STATUS_REGISTERED).to_a
      { login: users.index_by { |u| u.login.downcase }, mail: EmailAddress.where(user_id: users.map(&:id)).to_h { |e| [e.address.downcase, users.find { |u| u.id == e.user_id }] } }
    end

    def match(committer, idx)
      return nil if committer.blank?
      name, mail = committer.strip.match(/\A([^<]+?)\s*(?:<(.*)>)?\z/)&.captures
      idx[:login][name.to_s.strip.downcase] || (mail.present? ? idx[:mail][mail.downcase] : nil) || idx[:mail][committer.strip.downcase]
    end

    # 저장소 하나: { mapped: [[커미터, 사용자]], unmatched: [커미터], already: n }
    def refresh(repository, idx = user_index, remap: false)
      result = { mapped: [], unmatched: [], already: 0 }
      map = {}
      repository.committers.each do |committer, user_id|
        if user_id.to_i.positive? && !remap
          result[:already] += 1
          next
        end
        user = match(committer, idx)
        if user && user.id != user_id.to_i
          map[committer] = user.id
          result[:mapped] << [committer, user]
        elsif user
          result[:already] += 1
        else
          result[:unmatched] << committer
        end
      end
      repository.committer_ids = map if map.any?
      result
    end

    # 모든 저장소의 커미터 현황: [[저장소, 연결 수, 미연결 커미터 목록, 자동 연결 가능 수]]
    def overview(idx = user_index)
      Repository.includes(:project).to_a.map do |repo|
        list = repo.committers
        unmapped = list.reject { |_, uid| uid.to_i.positive? }.map(&:first)
        [repo, list.size - unmapped.size, unmapped, unmapped.count { |c| match(c, idx) }]
      end
    end

    # 사용자를 만들거나 로그인 ID 를 바꾸면, 그 ID 와 같은 미연결 커미터를 모든 저장소에서 연결
    def map_user(user)
      return unless user.is_a?(User) && user.login.present?
      Changeset.where(user_id: nil).where('LOWER(committer) = ? OR LOWER(committer) LIKE ?', user.login.downcase, "#{user.login.downcase} <%")
               .update_all(user_id: user.id)
    rescue StandardError => e
      Rails.logger.warn("[site_tools] 커미터 연결 실패: #{e.message}")
    end
  end
end
