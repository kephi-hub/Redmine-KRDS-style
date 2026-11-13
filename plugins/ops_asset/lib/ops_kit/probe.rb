# 자산 자동 확인
# - 서버 정보: 자산에 연결한 SSH 접속정보(vault_ssh 플러그인)로 OS·커널·호스트·CPU·메모리·디스크·가동 시간 수집 → 디스크 최대 사용률
# - 인증서: 주소(https://host[:port] 또는 host)로 TLS 접속해 인증서 만료일·이름·발급자 확인 → 인증서 자산은 만료일 갱신 (SSH 필요 없음)
require 'socket'
require 'openssl'
require 'timeout'
require 'json'

module OpsKit
  module Probe
    module_function

    DISK_WARN = 80
    CMDS = {
      'os' => "sed -n 's/^PRETTY_NAME=//p' /etc/os-release 2>/dev/null | tr -d '\"'",
      'kernel' => 'uname -sr',
      'host' => 'hostname',
      'cpus' => 'nproc 2>/dev/null',
      'cpu' => "grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2",
      'mem' => "free -m 2>/dev/null | awk '/^Mem:/{print $2\" \"$3}'",
      # GNU df 는 가상 파일시스템을 빼고, 안 되면(busybox 등) 전부 받아 아래에서 거름
      'disk' => '(df -P -k -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null || df -P -k 2>/dev/null) | tail -n +2',
      'uptime' => 'cat /proc/uptime 2>/dev/null'
    }.freeze

    VIRTUAL_FS = /\A(tmpfs|devtmpfs|overlay|shm|squashfs|none|udev|proc|sysfs|cgroup.*)\z/
    VIRTUAL_MOUNT = %r{\A/(dev|proc|sys|run)(/|\z)|\A/etc/(hosts|hostname|resolv\.conf)\z}

    def ssh_ready?
      defined?(SshConsole::Exec)
    end

    def parse_server(out)
      disks = out['disk'].to_s.lines.filter_map do |l|
        c = l.split(/\s+/)
        next unless c.size >= 6 && c[1].to_i.positive?
        next if (c[0].match?(VIRTUAL_FS) && c[5] != '/') || c[5].match?(VIRTUAL_MOUNT)
        { mount: c[5..].join(' '), size_kb: c[1].to_i, used_kb: c[2].to_i, pct: c[4].to_i }
      end.uniq { |d| d[:mount] }
      total, used = out['mem'].to_s.split.map(&:to_i)
      { os: out['os'].to_s.strip.presence || out['kernel'].to_s.strip, kernel: out['kernel'].to_s.strip, host: out['host'].to_s.strip,
        cpus: out['cpus'].to_i.positive? ? out['cpus'].to_i : nil, cpu: out['cpu'].to_s.strip.presence,
        mem_mb: total, mem_used_mb: used, disks: disks, uptime_days: (out['uptime'].to_f / 86_400).floor }
    end

    def summary(info)
      i = info.symbolize_keys
      [i[:os], (i[:cpus] && "#{i[:cpus]} vCPU"), (i[:mem_mb].to_i.positive? && "#{(i[:mem_mb] / 1024.0).round}GB")].select(&:present?).join(' · ')
    end

    # 서버 정보 수집 → { ok:, info: | error: }
    def server(asset, user: nil)
      raise I18n.t(:error_oa_no_ssh_plugin) unless ssh_ready?
      key = asset.vault_key or raise I18n.t(:error_oa_no_ssh_key)
      info = parse_server(SshConsole::Exec.run(key, CMDS, user: user))
      attrs = { server_info: info.to_json, disk_pct: info[:disks].map { |d| d[:pct] }.max, info_at: Time.current, info_error: nil }
      attrs[:spec] = summary(info) if asset.spec.blank?
      asset.update_columns(attrs)
      { ok: true, info: info }
    rescue StandardError => e
      asset.update_columns(info_at: Time.current, info_error: e.message.to_s.truncate(255))
      { ok: false, error: e.message }
    end

    # "https://www.sample.go.kr:8443/path" · "www.sample.go.kr" → [host, port]
    def host_port(address)
      a = address.to_s.strip.sub(%r{\A[a-z]+://}i, '').sub(%r{/.*\z}, '')
      a = a.sub(/\A[^@]*@/, '')
      return [Regexp.last_match(1), (Regexp.last_match(2) || 443).to_i] if a =~ /\A\[([^\]]+)\](?::(\d+))?\z/
      host, port = a.split(':', 2)
      [host.to_s, (port.presence || 443).to_i]
    end

    def peer_cert(host, port)
      Timeout.timeout(15) do
        sock = Socket.tcp(host, port, connect_timeout: 10)
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE
        ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
        ssl.hostname = host
        ssl.sync_close = true
        ssl.connect
        cert = ssl.peer_cert
        ssl.close
        cert
      end
    end

    def cn(name)
      name.to_a.find { |k, _, _| k == 'CN' }&.dig(1) || name.to_s
    end

    # 인증서 확인 → { ok:, info: | error: } — 인증서 자산은 만료일(expires_on)도 갱신
    def cert(asset)
      host, port = host_port(asset.address)
      raise I18n.t(:error_oa_no_address) if host.blank?
      c = peer_cert(host, port)
      san = c.extensions.find { |e| e.oid == 'subjectAltName' }&.value.to_s.scan(/DNS:([^,\s]+)/).flatten
      info = { host: host, port: port, subject: cn(c.subject), issuer: cn(c.issuer), not_before: c.not_before.to_date.to_s,
               not_after: c.not_after.to_date.to_s, san: san.first(20), match: san.any? { |n| n == host || (n.start_with?('*.') && host.end_with?(n[1..]) && host.count('.') == n.count('.')) } }
      attrs = { cert_info: info.to_json, cert_at: Time.current, cert_error: nil }
      attrs[:expires_on] = c.not_after.to_date if asset.kind == 'cert'
      asset.update_columns(attrs)
      { ok: true, info: info }
    rescue StandardError, Timeout::Error => e
      asset.update_columns(cert_at: Time.current, cert_error: e.message.to_s.truncate(255))
      { ok: false, error: e.message }
    end
  end
end
