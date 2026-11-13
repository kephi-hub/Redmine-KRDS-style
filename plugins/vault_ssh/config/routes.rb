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
