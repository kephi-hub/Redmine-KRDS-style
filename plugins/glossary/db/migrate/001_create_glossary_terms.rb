class CreateGlossaryTerms < ActiveRecord::Migration[7.2]
  def change
    create_table :glossary_terms do |t|
      t.integer :project_id                     # 비어 있으면 전사 공통 용어
      t.string :name, limit: 100, null: false   # 용어 (한글)
      t.string :name_en, limit: 200             # 영문명
      t.string :abbr, limit: 100                # 약어 (컬럼명 등, 예: CUST_NO)
      t.string :category, limit: 60             # 분류
      t.string :data_type, limit: 60            # 데이터 타입 (예: VARCHAR)
      t.string :data_length, limit: 30          # 길이 (예: 20, 10,2)
      t.text :definition                        # 정의
      t.text :note                              # 비고
      t.integer :author_id
      t.integer :updated_by_id
      t.timestamps
    end
    add_index :glossary_terms, [:project_id, :name], unique: true
    add_index :glossary_terms, :abbr
  end
end
