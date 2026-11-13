# 접속정보 › [SSH 설정] 모달 — 보기(폼 조각) · 저장 · 접속 시험 (저장 전 값으로)
class SshProfilesController < ApplicationController
  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_key

  def edit
    @profile = VaultSshProfile.for(@key)
    load_options
    render partial: 'ssh_profiles/form', layout: false
  end

  def update
    @profile = VaultSshProfile.for(@key)
    assign(@profile)
    if @profile.save
      render json: { ok: true, message: l(:notice_ssh_profile_saved) }
    else
      render json: { ok: false, message: @profile.errors.full_messages.join(', ') }, status: 422
    end
  end

  # 저장하지 않은 폼 값으로 실제 연결해 봄
  def test
    profile = VaultSshProfile.for(@key)
    assign(profile)
    unless profile.valid?
      return render json: { ok: false, message: profile.errors.full_messages.join(', ') }
    end
    ask = profile.auth == 'ask' ? { user: params[:ask_user].to_s, password: params[:ask_password].to_s } : nil
    chain = SshConsole::Target.chain(@key, profile, user: User.current, ask: ask)
    render json: SshConsole::Connector.test(chain)
  rescue SshConsole::TargetError => e
    render json: { ok: false, message: e.message, steps: [] }
  end

  private

  def find_key
    @key = Vault::Key.find_by(id: params[:key_id], project_id: @project.id)
    render_404 unless @key
    render_403 if @key && !SshConsole::Access.can_manage?(User.current, @key)
  end

  def load_options
    keys = SshConsole::Access.visible_keys(User.current, @project)
    @hop_keys = keys.select { |k| k.id != @key.id && SshConsole::Target.ssh_key?(k) }
    @key_files = keys.select { |k| k.is_a?(Vault::KeyFile) || k.is_a?(Vault::Sftp) }
  end

  # 폼 → 설정. 직접 입력 경유 서버의 비밀번호는 비워 두면 같은 자리의 기존 값 유지
  def assign(profile)
    load_options
    p = params[:ssh] || {}
    profile.port = p[:port].presence&.to_i
    profile.auth = p[:auth].to_s.presence_in(VaultSshProfile::AUTHS) || 'password'
    kf = p[:key_file_id].presence && @key_files.find { |k| k.id == p[:key_file_id].to_i }
    profile.key_file_id = kf&.id
    profile.key_pass_enc = VaultSshProfile.encrypt(p[:key_pass]) if p[:key_pass].present?
    profile.key_pass_enc = nil if p[:clear_key_pass] == '1'
    profile.env = p[:env].to_s.presence_in(VaultSshProfile::ENVS) || 'dev'
    profile.record = profile.env == 'prod' || p[:record] == '1'
    profile.start_cmd = p[:start_cmd].to_s.strip.truncate(255, omission: '').presence
    old = profile.hop_list
    reset = p[:reset_fp] == '1'
    learned = Array(p[:learned_fp])
    hops = []
    Array(p[:hops]&.values || p[:hops]).first(VaultSshProfile::MAX_HOPS).each_with_index do |h, i|
      h = h.respond_to?(:to_unsafe_h) ? h.to_unsafe_h : h.to_h
      prev = old[i] || {}
      if h['kind'] == 'key'
        hk = @hop_keys.find { |k| k.id == h['key_id'].to_i } or next
        same = prev['key_id'].to_i == hk.id
        hops << { 'key_id' => hk.id, 'fp' => (!reset && same ? prev['fp'] : nil) }
      else
        host = h['host'].to_s.strip
        next if host.empty?
        port = (h['port'].presence || 22).to_i
        user = h['user'].to_s.strip
        same = prev['host'] == host && prev['port'].to_i == port && prev['user'] == user
        secret = h['password'].present? ? VaultSshProfile.encrypt(h['password']) : (prev['host'] ? prev['secret_enc'] : nil)
        hops << { 'host' => host, 'port' => port, 'user' => user, 'secret_enc' => secret, 'fp' => (!reset && same ? prev['fp'] : nil) }
      end
    end
    hops.each_with_index { |h, i| h['fp'] ||= learned[i].presence }
    profile.hop_list = hops
    profile.host_key = nil if reset
    profile.host_key ||= learned[hops.size].presence
  end
end
