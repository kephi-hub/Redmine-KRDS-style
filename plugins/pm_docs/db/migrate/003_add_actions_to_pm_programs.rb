# 프로그램 처리 구분 (조회·등록·수정·삭제·다운로드… 쉼표로 여러 개)
class AddActionsToPmPrograms < ActiveRecord::Migration[7.2]
  def change
    add_column :pm_programs, :actions, :string, limit: 100
  end
end
