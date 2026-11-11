# DB 관리 경로
resources :db_servers, except: [:show] do
  member { post :test }
  collection { post :test_connection }
end
resources :projects, only: [] do
  resources :db_links, only: [:new, :create, :edit, :update, :destroy]
  get 'db', to: 'db_schemas#index', as: 'db_schemas'
  get 'db/compare', to: 'db_schemas#compare', as: 'db_compare'
  get 'db/:link_id/history', to: 'db_schemas#history', as: 'db_history'
  post 'db/:link_id/history', to: 'db_schemas#save_history'
  get 'db/:link_id/history/:id', to: 'db_schemas#history_diff', as: 'db_history_diff', constraints: { id: /\d+/ }
  match 'db/:link_id/query', to: 'db_schemas#query', via: [:get, :post], as: 'db_query'
  get 'db/:link_id/query/log', to: 'db_schemas#query_log', as: 'db_query_log'
  get 'db/:link_id/check', to: 'db_schemas#check', as: 'db_check'
  get 'db/:link_id/privacy', to: 'db_schemas#privacy', as: 'db_privacy'
  get 'db/:link_id/codes', to: 'db_schemas#codes', as: 'db_codes'
  post 'db/:link_id/codes', to: 'db_schemas#save_codes'
  post 'db/:link_id/privacy', to: 'db_schemas#save_privacy'
  get 'db/:link_id/erd', to: 'db_schemas#erd', as: 'db_erd', format: false
  get 'db/:link_id/export', to: 'db_schemas#export', as: 'db_export'
  get 'db/:link_id/objects/:kind/:key', to: 'db_schemas#object', as: 'db_object', constraints: { key: %r{[^/]+} }, format: false
  get 'db/:link_id/tables/:table', to: 'db_schemas#table', as: 'db_table', constraints: { table: %r{[^/]+} }, format: false
end
