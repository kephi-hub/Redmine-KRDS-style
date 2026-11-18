# 배포 가능 시간 — 정한 요일·시각(서울 시간)에만 배포 실행 (실수로 바로 배포하는 것 방지)
class AddDeployWindow < ActiveRecord::Migration[7.2]
  def change
    add_column :deploy_targets, :window_enabled, :boolean, null: false, default: false
    add_column :deploy_targets, :window_days, :string, limit: 20, null: false, default: '1,2,3,4,5'
    add_column :deploy_targets, :window_start, :string, limit: 5, null: false, default: '18:00'
    add_column :deploy_targets, :window_end, :string, limit: 5, null: false, default: '22:00'
  end
end
