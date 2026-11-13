resources :vault_key_types, except: [:show]
# 접속정보 목록 순서 저장 (드래그)
post 'projects/:project_id/keys_order', to: 'vault_key_orders#update', as: 'project_keys_order'
