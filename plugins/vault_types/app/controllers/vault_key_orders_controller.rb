# 접속정보 목록 순서 저장 — 화면(한 쪽)에 보이는 순서대로 ids 를 받아, 그 접속정보들이 차지하던 순번 자리에 새 순서로 넣음
# (다른 쪽·볼 수 없는 접속정보의 순번은 그대로). 순번이 없는 접속정보가 있으면 먼저 지금 목록 순서(순번 → 이름)로 매김
class VaultKeyOrdersController < ApplicationController
  before_action :find_project_by_project_id

  def update
    return deny_access unless User.current.allowed_to?(:edit_keys, @project)
    keys = Vault::Key.where(project_id: @project.id)
    ids = Array(params[:ids]).map(&:to_i).uniq & keys.pluck(:id)
    visible = keys.where(id: ids).to_a.select { |k| k.whitelisted?(User.current, @project) }.map(&:id)
    ids &= visible
    return render(json: { ok: false }, status: 422) if ids.size < 2
    Vault::Key.transaction do
      if keys.where(position: nil).exists?
        t = Vault::Key.table_name
        keys.order(Arel.sql("#{t}.position IS NULL"), :position, :name).pluck(:id).each_with_index do |id, i|
          Vault::Key.where(id: id).update_all(position: i + 1)
        end
      end
      slots = keys.where(id: ids).pluck(:position).sort
      ids.zip(slots).each { |id, pos| Vault::Key.where(id: id).update_all(position: pos) }
    end
    render json: { ok: true }
  end
end
