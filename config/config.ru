# frozen_string_literal: true

# Redmine 기본 config.ru 대신 마운트 (compose.yaml)
# RAILS_RELATIVE_URL_ROOT(.env 의 REDMINE_RELATIVE_URL_ROOT, 예: /pms) 가 있으면 그 경로 아래에서 서비스하고,
# 예전 주소(http://서버:3000/...)로 들어오면 같은 경로를 하위 경로 아래로 옮겨 줌 (즐겨찾기·cron 호환)
require_relative 'config/environment'

root = ActionController::Base.config.relative_url_root.to_s.chomp('/')
if root.empty?
  run Rails.application
else
  map(root) { run Rails.application }
  map('/') do
    run lambda { |env|
      path = env['PATH_INFO'].to_s
      query = env['QUERY_STRING'].to_s
      location = "#{root}#{path.empty? ? '/' : path}#{"?#{query}" unless query.empty?}"
      # GET·HEAD 는 302, 그 밖(POST 등)은 본문 유지를 위해 307
      status = %w[GET HEAD].include?(env['REQUEST_METHOD']) ? 302 : 307
      [status, { 'location' => location, 'content-type' => 'text/plain' }, []]
    }
  end
end
