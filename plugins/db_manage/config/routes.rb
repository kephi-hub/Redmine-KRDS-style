# DB 관리 경로
resources :db_servers, except: [:show] do
  member { post :test }
  collection { post :test_connection }
end
resources :projects, only: [] do
  resources :db_links, only: [:new, :create, :edit, :update, :destroy]
  get 'db', to: 'db_schemas#index', as: 'db_schemas'
  get 'db/compare', to: 'db_schemas#compare', as: 'db_compare'
  get 'db/:link_id/check', to: 'db_schemas#check', as: 'db_check'
  get 'db/:link_id/erd', to: 'db_schemas#erd', as: 'db_erd', format: false
  get 'db/:link_id/export', to: 'db_schemas#export', as: 'db_export'
  get 'db/:link_id/objects/:kind/:key', to: 'db_schemas#object', as: 'db_object', constraints: { key: %r{[^/]+} }, format: false
  get 'db/:link_id/tables/:table', to: 'db_schemas#table', as: 'db_table', constraints: { table: %r{[^/]+} }, format: false
end
