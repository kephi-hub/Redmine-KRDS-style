# 관리 도구: 메일 서버(SMTP), 저장소 커미터 자동 연결
get 'admin/smtp', to: 'smtp_settings#index', as: 'smtp_settings'
post 'admin/smtp', to: 'smtp_settings#update'
post 'admin/smtp/test', to: 'smtp_settings#test', as: 'test_smtp_settings'
get 'admin/committers', to: 'committer_maps#index', as: 'committer_maps'
post 'admin/committers', to: 'committer_maps#refresh', as: 'refresh_committer_maps'
