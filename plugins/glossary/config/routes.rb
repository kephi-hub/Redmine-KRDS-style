# 용어사전 — 프로젝트 용어사전과 전사 공통 용어사전(관리자)
resources :projects, only: [] do
  resources :glossary_terms, path: 'glossary', except: [:show] do
    collection do
      get :export
      match :import, via: [:get, :post]
    end
  end
end
resources :glossary_terms, path: 'glossary', except: [:show] do
  collection do
    get :export
    match :import, via: [:get, :post]
  end
end
