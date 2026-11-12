# 메뉴 구조도 · 시스템 권한
resources :projects, only: [] do
  get 'menus', to: 'menu_items#index', as: 'menu_items'
  post 'menus', to: 'menu_items#create'
  # 표 데이터 — .json 주소는 Redmine 이 API 요청(API 키 필요)으로 보므로 확장자 없는 주소로
  get 'menus/data', to: 'menu_items#data', as: 'menu_items_data'
  get 'menus/diagram', to: 'menu_items#diagram', as: 'menu_items_diagram'
  get 'menus/status', to: 'menu_items#status', as: 'menu_items_status'
  get 'menus/export', to: 'menu_items#export', as: 'menu_items_export'
  # 화면 캡처 (고정 주소를 :id 보다 먼저)
  get 'menus/captures', to: 'menu_captures#index', as: 'menu_captures'
  get 'menus/captures/settings', to: 'menu_captures#settings', as: 'menu_captures_settings'
  get 'menus/captures/document', to: 'menu_captures#document', as: 'menu_captures_document'
  get 'menus/captures/a11y', to: 'menu_captures#a11y', as: 'menu_captures_a11y'
  post 'menus/captures/settings', to: 'menu_captures#save_settings'
  post 'menus/captures/test', to: 'menu_captures#test_login', as: 'menu_captures_test'
  post 'menus/captures/run', to: 'menu_captures#run', as: 'menu_captures_run'
  get 'menus/captures/image/:id', to: 'menu_captures#image', as: 'menu_capture_image', constraints: { id: /\d+|login/ }
  get 'menus/captures/:id', to: 'menu_captures#show', as: 'menu_capture', constraints: { id: /\d+/ }
  post 'menus/captures/:id/a11y_issue', to: 'menu_captures#a11y_issue', as: 'menu_capture_a11y_issue', constraints: { id: /\d+/ }
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
