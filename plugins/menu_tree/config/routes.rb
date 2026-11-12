# 메뉴 구조도 · 시스템 권한
resources :projects, only: [] do
  get 'menus', to: 'menu_items#index', as: 'menu_items'
  post 'menus', to: 'menu_items#create'
  # 표 데이터 — .json 주소는 Redmine 이 API 요청(API 키 필요)으로 보므로 확장자 없는 주소로
  get 'menus/data', to: 'menu_items#data', as: 'menu_items_data'
  get 'menus/diagram', to: 'menu_items#diagram', as: 'menu_items_diagram'
  get 'menus/status', to: 'menu_items#status', as: 'menu_items_status'
  get 'menus/export', to: 'menu_items#export', as: 'menu_items_export'
  match 'menus/import', to: 'menu_items#import', via: [:get, :post], as: 'menu_items_import'
  post 'menus/issues', to: 'menu_items#issues', as: 'menu_items_issues'
  patch 'menus/:id', to: 'menu_items#update', as: 'menu_item', constraints: { id: /\d+/ }
  delete 'menus/:id', to: 'menu_items#destroy', constraints: { id: /\d+/ }
  post 'menus/:id/move', to: 'menu_items#move', as: 'move_menu_item', constraints: { id: /\d+/ }
  resources :menu_columns, only: [:create, :update, :destroy]
  resources :menu_sites, only: [:create, :update, :destroy]
  get 'sys_roles/matrix', to: 'sys_roles#matrix', as: 'sys_roles_matrix'
  post 'sys_roles/matrix', to: 'sys_roles#save_matrix'
  get 'sys_roles/export', to: 'sys_roles#export', as: 'sys_roles_export'
  resources :sys_roles, only: [:index, :new, :create, :edit, :update, :destroy]
end
