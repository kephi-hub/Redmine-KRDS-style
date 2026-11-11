# 관리 도구: 메일 서버(SMTP), 저장소 커미터 자동 연결
get 'admin/smtp', to: 'smtp_settings#index', as: 'smtp_settings'
post 'admin/smtp', to: 'smtp_settings#update'
post 'admin/smtp/test', to: 'smtp_settings#test', as: 'test_smtp_settings'
get 'admin/committers', to: 'committer_maps#index', as: 'committer_maps'
post 'admin/committers', to: 'committer_maps#refresh', as: 'refresh_committer_maps'
# 소스코드 다운로드 (repository_id·path·rev 는 주소 뒤 매개변수)
get 'projects/:project_id/source_export', to: 'repo_exports#show', as: 'repo_export'
