# Vault 원본 화면(app/views)을 한국어·개선 화면으로 고친다 — Docker 이미지 빌드 중 실행
#   ruby build.rb <vault 플러그인 경로> [출력 경로]
#   출력 경로를 생략하면 원본 화면을 그 자리에서 고침 (Dockerfile 방식)
# Vault 원본에는 라이선스 표기가 없어, 고친 화면 파일을 저장소에 넣지 않고 빌드할 때마다 원본에서 만들어 냄
# 원본이 바뀌어 문구를 못 찾으면 항목을 출력하고 실패(exit 1) → 이미지 빌드가 멈추므로 업그레이드 시 바로 알 수 있음
require "fileutils"
HERE = __dir__
SRC  = ARGV[0] or abort('사용: ruby build.rb <vault 플러그인 경로> [출력 경로]')
OUT  = ARGV[1] || SRC
snip = ->(name) { File.read(File.join(HERE, 'snippets', name), encoding: 'UTF-8') }

R = {
  "keys/_form.html.erb" => [
    ["</i> Generate",
     "</i> 생성"],
    ["title: \"Download file\"",
     "title: \"파일 다운로드\""],
    ["</i> Upload",
     "</i> 업로드"],
    [">Local Path:<",
     ">저장 경로:<"],
    ["'Are you sure you want to generate a new password? This will replace the current password.'",
     "'새 비밀번호를 생성할까요? 현재 비밀번호가 바뀝니다.'"],
  ],
  "keys/new.html.erb" => [
    ["<div class=\"pwd-container\">",
     "<h2 class=\"keys_tit\"><%= t('key.title.new') %></h2>\n<div class=\"pwd-container\">"],
    ["</i> Generate",
     "</i> 생성"],
    ["</i> Upload File",
     "</i> 파일 업로드"],
    ["title=\"Move to available\"",
     "title=\"선택 해제\""],
    ["title=\"Move to selected\"",
     "title=\"선택\""],
    [">Create<",
     ">등록<"],
    ["'Are you sure you want to generate a new password? This will replace the current password.'",
     "'새 비밀번호를 생성할까요? 현재 비밀번호가 바뀝니다.'"],
  ],
  "keys/edit.html.erb" => [
    ["<div class=\"pwd-container\">",
     "<h2 class=\"keys_tit\"><%= t('key.title.edit') %></h2>\n<div class=\"pwd-container\">"],
    ["</i> Generate",
     "</i> 생성"],
    [">Current file:<",
     ">현재 파일:<"],
    ["</i> Upload New File",
     "</i> 새 파일 업로드"],
    ["title=\"Move to available\"",
     "title=\"선택 해제\""],
    ["title=\"Move to selected\"",
     "title=\"선택\""],
    [">Save<",
     ">저장<"],
    ["'Are you sure you want to generate a new password? This will replace the current password.'",
     "'새 비밀번호를 생성할까요? 현재 비밀번호가 바뀝니다.'"],
  ],
  "keys/show.html.erb" => [
    ["<div class=\"pwd-container\">",
     "<h2 class=\"keys_tit\"><%= t('key.title.show') %></h2>\n<div class=\"pwd-container\">"],
    ["title: \"Download file\"",
     "title: \"파일 다운로드\""],
    [">Local Path:<",
     ">저장 경로:<"],
    [">No file attached<",
     ">첨부 파일 없음<"],
    ["onclick=\"navigator.clipboard.writeText('<%= @key.url %>')\"",
     "data-copy=\"<%= @key.url %>\""],
    ["onclick=\"navigator.clipboard.writeText('<%= @key.login %>')\"",
     "data-copy=\"<%= @key.login %>\""],
    ["onclick=\"navigator.clipboard.writeText('<%= @key.body %>')\"",
     "data-copy=\"<%= @key.body %>\""],
    ["<div class=\"pwd-field-value pwd-type-value\"><%= @key.type %></div>",
     "<div class=\"pwd-field-value pwd-type-value\"><%= t(\"activerecord.models.\#{@key.type.to_s.underscore.split('/').last}\") %></div>"],
    ["<span class=\"pwd-field-value pwd-password\" id=\"password-body\"><%= @key.body %></span>",
     "<span class=\"pwd-field-value pwd-password\" id=\"password-body\" data-secret=\"<%= @key.body %>\">••••••••</span>\n              <button type=\"button\" class=\"pwd-copy-btn pwd-reveal-btn\" title=\"보기\" aria-pressed=\"false\"><i class=\"fa fa-eye\"></i></button>"],
  ],
  "shared/_key_fields.html.erb" => [
    ["link_to key.name, edit_project_key_path(key.project, key)",
     "link_to key.name, project_key_path(key.project, key)"],
  ],
  "shared/_key_fields_all.html.erb" => [
    ["link_to key.name, edit_project_key_path(key.project, key)",
     "link_to key.name, project_key_path(key.project, key)"],
  ],
  "keys/index.html.erb" => [
    ["<%= form_tag({}) do %>",
     "__TOOLBAR__<%= form_tag({}) do %>"],
    ["</table>\n<% end %>",
     "</table>\n<% end %>\n__BOTTOM__"],
  ],
  "keys/all.html.erb" => [
    ["<%= form_tag({}) do %>",
     "__TOOLBAR__<%= form_tag({}) do %>"],
    ["  </table>\n<% end %>",
     "  </table>\n<% end %>\n__BOTTOM__"],
  ],
  "keys/edit_orphaned.html.erb" => [
    ["(Type: ",
     "(유형: "],
  ],
  "vault/sftps/_sftp.html.erb" => [
    ["title: \"Download file\"",
     "title: \"파일 다운로드\""],
  ],
  "vault/sftps/_sftp_all.html.erb" => [
    ["title: \"Download file\"",
     "title: \"파일 다운로드\""],
  ],
  "vault/key_files/_key_file.html.erb" => [
    ["title: \"Download file\"",
     "title: \"파일 다운로드\""],
  ],
  "tags/index.html.erb" => [
    [">Tags<",
     ">태그<"],
    [">Name<",
     ">이름<"],
    [">Color<",
     ">색상<"],
  ],
  "vault_settings/index.html.erb" => [
    [">Admin Tools<",
     ">관리 도구<"],
    ["Check which users have access to which keys and understand why. Useful for debugging permissions and planning migration to tag-based permissions.",
     "어떤 사용자가 어떤 접속정보에 접근할 수 있는지, 그 이유와 함께 확인합니다. 권한 점검이나 태그 기반 권한으로 옮길 때 유용합니다."],
    ["</i> Generate",
     "</i> 생성"],
    [">Encrypt Files<",
     ">파일 암호화<"],
    ["When enabled, all uploaded files will be encrypted on disk. When disabled, all files will be decrypted.",
     "켜면 업로드한 파일을 디스크에 암호화해 저장합니다. 끄면 모든 파일을 복호화합니다."],
    ["⚠️ Important: Backup Before Enabling/Disabling",
     "⚠️ 중요: 켜거나 끄기 전에 반드시 백업하세요"],
    ["Before toggling this setting, manually backup your files by copying the",
     "설정을 바꾸기 전에"],
    ["directory to another location on the server. This protects against data loss if the encryption/decryption process encounters errors.",
     "폴더를 서버의 다른 위치에 직접 복사해 백업하세요. 암호화·복호화 중 오류가 나도 파일을 잃지 않습니다."],
    ["How to backup (run in terminal from Rails root):",
     "백업 방법 (Rails 루트에서 터미널로 실행):"],
    ["= create backup folder",
     "= 백업 폴더 생성"],
    ["= run next command if first succeeds",
     "= 앞 명령이 성공하면 다음 명령 실행"],
    ["= copy all files",
     "= 모든 파일 복사"],
    ["'Are you sure you want to regenerate the encryption key? This will replace the current key.'",
     "'암호화 키를 새로 생성할까요? 현재 키가 바뀝니다.'"],
  ],
  "vault_admin/permissions_audit.html.erb" => [
    [">Vault Permissions Audit<",
     ">접속정보 권한 점검<"],
    [">Check which keys users can access and understand why.<",
     ">사용자가 어떤 접속정보에 접근할 수 있는지, 그 이유와 함께 확인합니다.<"],
    [">Which Keys Can User Access?<",
     ">사용자별 접근 가능한 접속정보<"],
    [">Select User:<",
     ">사용자 선택:<"],
    ["'Choose user...'",
     "'사용자를 선택하세요'"],
    ["Access Summary for <%= @selected_user.name %>",
     "<%= @selected_user.name %> 접근 요약"],
    [">Total Keys<",
     ">전체 접속정보<"],
    [">Via Admin<",
     ">관리자 권한<"],
    [">Via Permissions<",
     ">역할 권한<"],
    [">Via Whitelist<",
     ">접근 목록<"],
    [">Key Name<",
     ">접속정보 이름<"],
    [">Project<",
     ">프로젝트<"],
    [">Type<",
     ">유형<"],
    [">Access Reason<",
     ">접근 사유<"],
    [">Details<",
     ">상세<"],
    [">Actions<",
     ">작업<"],
    ["📋 Migration Information",
     "📋 전환 안내"],
    ["This user has access to <strong><%= @access_reasons['whitelist']&.count || 0 %> keys via whitelist</strong>.",
     "이 사용자는 <strong>접근 목록으로 <%= @access_reasons['whitelist']&.count || 0 %>개</strong>의 접속정보에 접근합니다."],
    ["<strong>Tip:</strong> Whitelist entries are being deprecated.",
     "<strong>참고:</strong> 접근 목록 방식은 앞으로 지원이 중단될 예정입니다."],
    ["User <%= @selected_user.name %> has access to no keys.",
     "<%= @selected_user.name %> 사용자가 접근할 수 있는 접속정보가 없습니다."],
    [">Which Users Can Access Key?<",
     ">접속정보별 접근 가능한 사용자<"],
    [">Select Key:<",
     ">접속정보 선택:<"],
    ["'Choose key...'",
     "'접속정보를 선택하세요'"],
    ["Users with Access to \"<%= @selected_key.name %>\"",
     "\"<%= @selected_key.name %>\" 접근 가능 사용자"],
    [">Project:<",
     ">프로젝트:<"],
    [">Type:<",
     ">유형:<"],
    [">Tags:<",
     ">태그:<"],
    ["<em>No tags</em>",
     "<em>태그 없음</em>"],
    [">Whitelist:<",
     ">접근 목록:<"],
    ["<%= @selected_key.whitelist.split(',').length %> entries</strong>",
     "<%= @selected_key.whitelist.split(',').length %>명</strong>"],
    ["<em>Empty</em>",
     "<em>없음</em>"],
    [">Total Users<",
     ">전체 사용자<"],
    [">User<",
     ">사용자<"],
    [">Login<",
     ">아이디<"],
    [">Groups<",
     ">그룹<"],
    [">Access Source<",
     ">접근 경로<"],
    [">Reason<",
     ">사유<"],
    ["This key has <strong><%= @selected_key.whitelist.split(',').length %> whitelist entries</strong>.",
     "이 접속정보의 접근 목록에 <strong><%= @selected_key.whitelist.split(',').length %>명</strong>이 있습니다."],
    ["<strong>Tip:</strong> Consider moving to tag-based permissions.",
     "<strong>참고:</strong> 태그 기반 권한으로 옮기는 것을 고려하세요."],
    ["<strong>ℹ️ Tags on this key:</strong>",
     "<strong>ℹ️ 이 접속정보의 태그:</strong>"],
    ["No users have access to this key.",
     "이 접속정보에 접근할 수 있는 사용자가 없습니다."],
  ],
}.freeze

# 머리줄 검색 입력칸(th) → 일반 제목
TH_RE = /<th style="padding: 4px;">\s*<%= text_field_tag\(:filter_(\w+),.*?%>\s*<\/th>/m
TH_FN = ->(m) { "<th><%= t('key.attr.#{m[1]}') %></th>" }
REGEX = { 'keys/index.html.erb' => 5, 'keys/all.html.erb' => 6 }.freeze
APPEND = { 'keys/index.html.erb' => 'list_script.erb', 'keys/all.html.erb' => 'list_script.erb', 'keys/show.html.erb' => 'show_script.erb' }.freeze

fail_count = 0
R.each do |rel, pairs|
  src = File.read(File.join(SRC, 'app', 'views', rel), encoding: 'UTF-8')
  pairs.each do |old, new|
    unless src.include?(old)
      puts "[못 찾음] #{rel}: #{old[0, 60]}"; fail_count += 1; next
    end
    src = src.gsub(old) { new }
  end
  src = src.gsub('__TOOLBAR__') { snip.('list_toolbar.erb') + "\n" }
  src = src.gsub('__BOTTOM__') { snip.('list_bottom.erb') }
  if (want = REGEX[rel])
    n = src.scan(TH_RE).size
    src = src.gsub(TH_RE) { TH_FN.(Regexp.last_match) }
    if n != want
      puts "[개수 다름] #{rel}: 머리줄 입력칸 #{n}개 (기대 #{want})"; fail_count += 1
    end
  end
  src = src.sub(/\n+\z/, '') + "\n\n" + snip.(APPEND[rel]) if APPEND[rel]
  dst = File.join(OUT, 'app', 'views', rel)
  FileUtils.mkdir_p(File.dirname(dst))
  File.write(dst, src)
  puts "[완료] #{rel} (#{pairs.size}건)"
end
exit(fail_count.zero? ? 0 : 1)
