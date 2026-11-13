# SSH 명령 실행 (다른 기능용) — 접속정보 "SSH 서버" + 접속 설정(경유 포함)으로 연결해 명령 몇 개를 실행하고 바로 닫음
# 스케줄러 crontab 수집 · 자산 서버 정보 수집이 씀. "접속할 때 입력" 서버는 비밀번호가 없어 쓸 수 없음
require 'timeout'

module SshConsole
  module Exec
    module_function

    # commands: { 이름 => 명령 } → { 이름 => 출력 } (명령마다 30초)
    def run(key, commands, user: nil, timeout: 30)
      raise TargetError, I18n.t(:error_ssh_not_ssh) unless key && Target.ssh_key?(key)
      profile = VaultSshProfile.find_by(key_id: key.id)
      raise TargetError, I18n.t(:error_ssh_exec_ask) if profile&.auth == 'ask'
      user ||= User.active.where(admin: true).first
      chain = Target.chain(key, profile, user: user)
      link = Connector.open(chain)
      Target.remember(profile, chain, link.fingerprints) if profile
      begin
        commands.to_h do |name, cmd|
          out = Timeout.timeout(timeout) { link.ssh.exec!(cmd) }
          [name, out.to_s.dup.force_encoding('UTF-8').scrub]
        end
      ensure
        link.close
      end
    end
  end
end
