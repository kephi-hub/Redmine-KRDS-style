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
  get 'programs/export', to: 'pm_programs#export', as: 'pm_programs_export'
  match 'programs/import', to: 'pm_programs#import', via: [:get, :post], as: 'pm_programs_import'
  resources :pm_programs, path: 'programs'
  resources :pm_meetings, path: 'meetings'
  get 'risks/export', to: 'pm_risks#export', as: 'pm_risks_export'
  resources :pm_risks, path: 'risks'
end
