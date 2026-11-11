# 공통코드 정의서 — DB 연결마다 코드 테이블·컬럼 지정 (JSON)
class AddCodeConfigToDbLinks < ActiveRecord::Migration[7.2]
  def change
    add_column :db_links, :code_config, :text
  end
end
