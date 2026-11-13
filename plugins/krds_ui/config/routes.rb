# 관리 > 메뉴·모듈 이름
get 'admin/labels', to: 'krds_labels#index', as: 'krds_labels'
post 'admin/labels', to: 'krds_labels#save'
post 'admin/labels/reset', to: 'krds_labels#reset', as: 'krds_labels_reset'
