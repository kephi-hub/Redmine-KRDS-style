# Jenkins 배포 연동 경로
resources :jenkins_servers, except: [:show] do
  member { post :test }
end
resources :projects, only: [] do
  resources :deploy_targets, only: [:new, :create, :edit, :update, :destroy]
  get 'deploys', to: 'deploys#index', as: 'deploys'
  get 'deploys/status', to: 'deploys#status', as: 'deploys_status'
  post 'deploys', to: 'deploys#create'
end
