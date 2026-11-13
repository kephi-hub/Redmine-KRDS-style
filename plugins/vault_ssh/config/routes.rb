# SSH 터미널
resources :projects, only: [] do
  post 'keys/:key_id/ssh', to: 'ssh_sessions#create', as: 'key_ssh', constraints: { key_id: /\d+/ }
  get 'keys/:key_id/ssh_profile', to: 'ssh_profiles#edit', as: 'key_ssh_profile', constraints: { key_id: /\d+/ }
  post 'keys/:key_id/ssh_profile', to: 'ssh_profiles#update', constraints: { key_id: /\d+/ }
  post 'keys/:key_id/ssh_profile/test', to: 'ssh_profiles#test', as: 'key_ssh_profile_test', constraints: { key_id: /\d+/ }
  get 'ssh_sessions', to: 'ssh_sessions#index', as: 'ssh_sessions'
  get 'ssh_sessions/export', to: 'ssh_sessions#export', as: 'ssh_sessions_export'
  get 'ssh_sessions/:id', to: 'ssh_sessions#show', as: 'ssh_session', constraints: { id: /\d+/ }
  get 'ssh_sessions/:id/cast', to: 'ssh_sessions#cast', as: 'ssh_session_cast', constraints: { id: /\d+/ }
end
get 'ssh/t/:ticket', to: 'ssh_sessions#terminal', as: 'ssh_terminal', constraints: { ticket: /[\w-]+/ }
post 'ssh/t/:ticket/again', to: 'ssh_sessions#again', as: 'ssh_terminal_again', constraints: { ticket: /[\w-]+/ }
# 터미널 파일 창 (SFTP)
get 'ssh/t/:ticket/files', to: 'ssh_files#index', as: 'ssh_files', constraints: { ticket: /[\w-]+/ }
get 'ssh/t/:ticket/files/download', to: 'ssh_files#download', as: 'ssh_files_download', constraints: { ticket: /[\w-]+/ }
post 'ssh/t/:ticket/files/upload', to: 'ssh_files#upload', as: 'ssh_files_upload', constraints: { ticket: /[\w-]+/ }
post 'ssh/t/:ticket/files/mkdir', to: 'ssh_files#mkdir', as: 'ssh_files_mkdir', constraints: { ticket: /[\w-]+/ }
post 'ssh/t/:ticket/files/rename', to: 'ssh_files#rename', as: 'ssh_files_rename', constraints: { ticket: /[\w-]+/ }
post 'ssh/t/:ticket/files/delete', to: 'ssh_files#delete', as: 'ssh_files_delete', constraints: { ticket: /[\w-]+/ }
