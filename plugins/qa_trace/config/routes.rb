# 요구사항 · 테스트 (고정 주소를 resources 보다 먼저 — trace·export 가 :id 로 잡히지 않게)
resources :projects, only: [] do
  get 'requirements/trace', to: 'qa_requirements#trace', as: 'qa_requirements_trace'
  get 'requirements/export', to: 'qa_requirements#export', as: 'qa_requirements_export'
  match 'requirements/import', to: 'qa_requirements#import', via: [:get, :post], as: 'qa_requirements_import'
  resources :qa_requirements, path: 'requirements'
  get 'tests/menus', to: 'qa_test_cases#menus', as: 'qa_test_cases_menus'
  get 'tests/export', to: 'qa_test_cases#export', as: 'qa_test_cases_export'
  match 'tests/import', to: 'qa_test_cases#import', via: [:get, :post], as: 'qa_test_cases_import'
  resources :qa_test_cases, path: 'tests'
  resources :qa_test_runs, path: 'test_runs' do
    member do
      post :save
      post :defect
      post :sync
      get :export
    end
  end
end
