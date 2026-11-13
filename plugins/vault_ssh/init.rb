# SSH 브라우저 터미널 — 접속정보(Vault) "SSH 서버" 에서 [접속] → 새 탭 터미널 (xterm.js + ActionCable + net-ssh)
# - SSH 설정(포트·인증·경유 서버 최대 3대·지문·시작 명령·구분·녹화): 접속정보 목록·상세의 [SSH 설정] 모달
# - SSH 연결 코드는 이 플러그인 안에서만 씀 (DB 관리 SSH 터널과 별개)
# - 접속 기록 · 화면 녹화(asciinema cast, files/ssh_records — PMS 백업에 포함) · 재생 · 엑셀
# - assets/javascripts/xterm*.js · stylesheets/xterm.css : xterm.js 5.5.0 + addon-fit 0.10.0 (MIT, xterm-LICENSE.txt)
require_relative 'lib/ssh_console/target'
require_relative 'lib/ssh_console/connector'
require_relative 'lib/ssh_console/recorder'
require_relative 'lib/ssh_console/runner'
require_relative 'lib/ssh_console/access'
require_relative 'lib/ssh_console/sheet'
require_relative 'lib/ssh_console/files'
require_relative 'lib/ssh_console/exec'
require_relative 'lib/ssh_console/cable'
require_relative 'lib/ssh_console/terminal_channel'
require_relative 'lib/ssh_console/hooks'

Redmine::Plugin.register :vault_ssh do
  name 'SSH 터미널'
  author 'kephi-hub'
  description '접속정보(Vault) SSH 서버에 브라우저 터미널로 접속 — 경유 서버, 접속 기록·녹화'
  version '1.0.0'
  url 'https://github.com/kephi-hub/Redmine-KRDS-style'
  requires_redmine version_or_higher: '6.0'
  requires_redmine_plugin :vault, version_or_higher: '0.10.5'

  permission :use_ssh_terminal, { ssh_sessions: [:create, :index, :show, :cast, :export] }, project_module: :keys, require: :member
  permission :use_ssh_terminal_prod, { ssh_sessions: [:create, :index, :show, :cast, :export] }, project_module: :keys, require: :member
  permission :manage_ssh_profiles, { ssh_profiles: [:edit, :update, :test] }, project_module: :keys, require: :member
  permission :view_ssh_sessions, { ssh_sessions: [:index, :show, :cast, :export] }, project_module: :keys, read: true
end

Vault::Key.has_one :ssh_profile, class_name: 'VaultSshProfile', foreign_key: :key_id, dependent: :destroy unless Vault::Key.reflect_on_association(:ssh_profile)

# ActionCable — puma 프로세스 하나 안에서(async), 출처·로그인 확인은 SshConsole::Cable::Connection 에서
ActionCable.server.config.cable = { 'adapter' => 'async' } if ActionCable.server.config.cable.blank?
ActionCable.server.config.disable_request_forgery_protection = true
ActionCable.server.config.connection_class = -> { SshConsole::Cable::Connection }
ActionCable.server.config.logger = Rails.logger
