# 접속정보 목록 순서 (드래그로 정렬) — 비어 있으면 이름순 뒤에
class AddPositionToKeys < ActiveRecord::Migration[7.2]
  def change
    add_column :keys, :position, :integer
    add_index :keys, [:project_id, :position]
  end
end
