# 자산 · 스케줄러 · 점검·장애 · 인터페이스 (고정 주소를 resources 보다 먼저)
resources :projects, only: [] do
  get 'assets/export', to: 'ops_assets#export', as: 'ops_assets_export'
  post 'assets/link', to: 'ops_assets#link', as: 'ops_assets_link'
  delete 'assets/:id/link', to: 'ops_assets#unlink', as: 'ops_asset_unlink', constraints: { id: /\d+/ }
  post 'assets/:id/collect', to: 'ops_assets#collect', as: 'ops_asset_collect', constraints: { id: /\d+/ }
  post 'assets/:id/cert', to: 'ops_assets#cert', as: 'ops_asset_cert', constraints: { id: /\d+/ }
  resources :ops_assets, path: 'assets', except: [:show]
  get 'schedules/timeline', to: 'ops_schedules#timeline', as: 'ops_schedules_timeline'
  get 'schedules/export', to: 'ops_schedules#export', as: 'ops_schedules_export'
  get 'schedules/preview', to: 'ops_schedules#preview', as: 'ops_schedules_preview'
  match 'schedules/import', to: 'ops_schedules#import', via: [:get, :post], as: 'ops_schedules_import'
  resources :ops_schedules, path: 'schedules'
  get 'ops/report', to: 'ops_reports#index', as: 'ops_report'
  resources :ops_incidents, path: 'incidents'
  resources :ops_checks, path: 'checks'
  resources :ops_check_templates, path: 'check_templates', only: [:new, :create, :edit, :update, :destroy]
  get 'interfaces/diagram', to: 'ops_interfaces#diagram', as: 'ops_interfaces_diagram'
  get 'interfaces/export', to: 'ops_interfaces#export', as: 'ops_interfaces_export'
  resources :ops_interfaces, path: 'interfaces'
end
resources :admin_ops_assets, path: 'admin/assets', except: [:show]
