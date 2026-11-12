# 테스트 케이스 ↔ 프로그램(기능) 연결 — 단위테스트를 프로그램 ID 기준으로
class AddProgramToQaTestCases < ActiveRecord::Migration[7.2]
  def change
    add_column :qa_test_cases, :pm_program_id, :integer
    add_index :qa_test_cases, :pm_program_id
  end
end
