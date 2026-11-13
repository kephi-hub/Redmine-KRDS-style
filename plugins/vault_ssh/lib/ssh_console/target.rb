# 접속 대상 풀이 — 접속정보(Vault) + SSH 설정 → [경유 서버..., 대상] 단계 목록
# 비밀값은 여기서만 꺼내고 화면·로그로 내보내지 않음
module SshConsole
  Endpoint = Struct.new(:label, :host, :port, :user, :password, :key_data, :passphrase, :fingerprint, :hop_index, keyword_init: true) do
    def to_s
      "#{user}@#{host}:#{port}"
    end
  end

  class TargetError < StandardError; end

  module Target
    module_function

    # "10.0.0.16:2222", "ssh://deploy@host:22", "[::1]:22", "host" → [host, port, user]
    def parse(url, default_port = 22)
      u = url.to_s.strip.sub(%r{\Assh://}i, '').sub(%r{/.*\z}, '')
      user = nil
      if (m = u.match(/\A([^@\s]+)@(.+)\z/))
        user, u = m[1], m[2]
      end
      if (m = u.match(/\A\[([^\]]+)\](?::(\d+))?\z/))
        [m[1], (m[2] || default_port).to_i, user]
      elsif (m = u.match(/\A([^:\s]+):(\d+)\z/))
        [m[1], m[2].to_i, user]
      else
        [u, default_port.to_i, user]
      end
    end

    # 접속정보 비밀값 — DB 에서 읽은 직후는 암호화된 상태라, 새로 읽은 복사본을 복호화해 씀 (원래 객체는 건드리지 않음)
    def secret(key)
      fresh = Vault::Key.find_by(id: key.id) or return nil
      fresh.decrypt! if fresh.respond_to?(:decrypt!)
      fresh.body.presence
    rescue StandardError
      nil
    end

    def ssh_key?(key)
      return false unless key.is_a?(Vault::Password)
      name = key.respond_to?(:vault_type) ? key.vault_type&.name.to_s : ''
      name.match?(/SSH/i)
    end

    # 접속정보 하나 → 단계 하나 (ask: 접속할 때 입력한 { user:, password: })
    def endpoint(key, profile, ask: nil, label: nil)
      profile ||= VaultSshProfile.new(key_id: key.id)
      host, port, url_user = parse(key.url, profile.port.presence || 22)
      port = profile.port if profile.port.present?
      raise TargetError, I18n.t(:error_ssh_no_host, name: key.name) if host.blank?
      user = key.login.presence || url_user
      ep = Endpoint.new(label: label || key.name, host: host, port: port, user: user)
      case profile.auth
      when 'key'
        kf = Vault::Key.find_by(id: profile.key_file_id, project_id: key.project_id)
        raise TargetError, I18n.t(:error_ssh_key_file) unless kf.is_a?(Vault::KeyFile) || kf.is_a?(Vault::Sftp)
        data = kf.respond_to?(:file_content) ? kf.file_content.to_s : ''
        raise TargetError, I18n.t(:error_ssh_key_file) if data.blank?
        ep.key_data = data
        ep.passphrase = profile.key_pass.presence || secret(kf)
      when 'ask'
        ep.user = ask[:user].presence || user if ask
        ep.password = ask && ask[:password]
        raise TargetError, I18n.t(:error_ssh_ask_needed) if ep.password.blank?
      else
        ep.password = secret(key)
      end
      raise TargetError, I18n.t(:error_ssh_no_user, name: key.name) if ep.user.blank?
      ep
    end

    # 경유 서버 + 대상. 경유 접속정보는 같은 프로젝트의 "SSH 서버" 이고 그 사용자가 볼 수 있어야 함
    def chain(key, profile, user:, ask: nil)
      list = []
      (profile&.hop_list || []).each_with_index do |h, i|
        ep = if h['key_id'].present?
               hk = Vault::Key.find_by(id: h['key_id'], project_id: key.project_id)
               raise TargetError, I18n.t(:error_ssh_hop_missing, n: i + 1) unless hk && ssh_key?(hk) && hk.whitelisted?(user, hk.project)
               hp = VaultSshProfile.find_by(key_id: hk.id)
               hp = nil if hp&.auth == 'ask'
               endpoint(hk, hp, label: hk.name)
             else
               Endpoint.new(label: h['host'], host: h['host'].to_s.strip, port: (h['port'].presence || 22).to_i, user: h['user'].to_s.strip,
                            password: VaultSshProfile.decrypt(h['secret_enc']))
             end
        ep.fingerprint = h['fp'].presence
        ep.hop_index = i
        list << ep
      end
      target = endpoint(key, profile, ask: ask)
      target.fingerprint = profile&.host_key.presence
      list << target
    end

    # 처음 연결 때 본 지문을 접속 설정에 기록 (비어 있는 칸만)
    def remember(profile, chain, fps)
      return unless profile&.persisted?
      changed = false
      hops = profile.hop_list
      chain.each_with_index do |_, i|
        fp = fps[i] or next
        if i == chain.size - 1
          (profile.host_key = fp; changed = true) if profile.host_key.blank?
        elsif hops[i] && hops[i]['fp'].blank?
          hops[i]['fp'] = fp
          changed = true
        end
      end
      return unless changed
      profile.hop_list = hops
      profile.save(validate: false)
    end

    # 화면용 경로 설명 (비밀값 없음): "deploy@10.0.0.16:2222 · 경유 WEB1"
    def describe(chain)
      t = chain.last
      via = chain[0..-2].map(&:label)
      [t.to_s, (via.any? ? "#{I18n.t(:label_ssh_via)} #{via.join(' → ')}" : nil)].compact.join(' · ')
    end
  end
end
