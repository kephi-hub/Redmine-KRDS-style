# 산출물 · 변경요청 · 프로그램 목록 · 회의록 · 이슈·위험 (고정 주소를 resources 보다 먼저)
resources :projects, only: [] do
  post 'deliverables/seed', to: 'pm_deliverables#seed', as: 'pm_deliverables_seed'
  match 'deliverables/package', to: 'pm_deliverables#package', via: [:get, :post], as: 'pm_deliverables_package'
  resources :pm_deliverables, path: 'deliverables' do
    member do
      post :attach
      post :review
      get :generate
    end
  end
  get 'change_requests/export', to: 'pm_change_requests#export', as: 'pm_change_requests_export'
  resources :pm_change_requests, path: 'change_requests' do
    member do
      post :decide
      post :make_issue
    end
  end
  post 'programs/from_menus', to: 'pm_programs#from_menus', as: 'pm_programs_from_menus'
  match 'programs/suggest', to: 'pm_programs#suggest', via: [:get, :post], as: 'pm_programs_suggest'
  match 'programs/status_suggest', to: 'pm_programs#status_suggest', via: [:get, :post], as: 'pm_programs_status_suggest'
  get 'programs/export', to: 'pm_programs#export', as: 'pm_programs_export'
  match 'programs/import', to: 'pm_programs#import', via: [:get, :post], as: 'pm_programs_import'
  resources :pm_programs, path: 'programs'
  resources :pm_meetings, path: 'meetings'
  get 'risks/export', to: 'pm_risks#export', as: 'pm_risks_export'
  resources :pm_risks, path: 'risks'
  # 감리 · 투입 인력 · 보안약점 · 보고서
  get 'audits/export', to: 'pm_audits#export', as: 'pm_audits_export'
  match 'audits/import', to: 'pm_audits#import', via: [:get, :post], as: 'pm_audits_import'
  resources :pm_audit_rounds, path: 'audit_rounds', only: [:new, :create, :edit, :update, :destroy]
  resources :pm_audits, path: 'audits'
  get 'staff/export', to: 'pm_staffs#export', as: 'pm_staffs_export'
  resources :pm_staffs, path: 'staff', except: [:show]
  get 'sec_scans/:id/export', to: 'pm_sec_scans#export', as: 'pm_sec_scan_export', constraints: { id: /\d+/ }
  post 'sec_scans/:id/bulk', to: 'pm_sec_scans#bulk', as: 'pm_sec_scan_bulk', constraints: { id: /\d+/ }
  resources :pm_sec_scans, path: 'sec_scans'
  get 'reports', to: 'pm_reports#index', as: 'pm_reports'
  get 'reports/export', to: 'pm_reports#export', as: 'pm_reports_export'
end
# 전체 프로젝트 현황 (PMO)
get 'pmo', to: 'pm_portfolio#index', as: 'pm_portfolio'
get 'pmo/export', to: 'pm_portfolio#export', as: 'pm_portfolio_export'
