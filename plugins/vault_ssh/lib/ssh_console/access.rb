# 권한 — Vault 권한(보기 + 허용 목록)을 그대로 따르고, 터미널 권한을 더 봄
module SshConsole
  BOOTED_AT = Time.current
  # 운영 서버 접속에 2단계 인증 필수 (끄려면 컨테이너 환경변수 SSH_PROD_2FA=0)
  PROD_2FA = ENV.fetch('SSH_PROD_2FA', '1') != '0'

  module Access
    module_function

    def key_ok?(user, key)
      key && key.project && Target.ssh_key?(key) && user.allowed_to?(:view_keys, key.project) && key.whitelisted?(user, key.project)
    end

    def connect_perm(profile)
      profile&.prod? ? :use_ssh_terminal_prod : :use_ssh_terminal
    end

    def can_connect?(user, key, profile = VaultSshProfile.find_by(key_id: key&.id))
      key_ok?(user, key) && user.allowed_to?(connect_perm(profile), key.project)
    end

    def can_manage?(user, key)
      key_ok?(user, key) && user.allowed_to?(:manage_ssh_profiles, key.project) && user.allowed_to?(:edit_keys, key.project)
    end

    def can_view_all?(user, project)
      user.allowed_to?(:view_ssh_sessions, project)
    end

    # 같은 프로젝트에서 그 사용자가 볼 수 있는 접속정보 (경유 서버 · 키 파일 고르기)
    def visible_keys(user, project)
      Vault::Key.where(project_id: project.id).includes(:vault_type).to_a.select { |k| k.whitelisted?(user, project) }
    end
  end
end
