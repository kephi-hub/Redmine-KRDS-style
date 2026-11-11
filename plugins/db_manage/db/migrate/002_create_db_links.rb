class CreateDbLinks < ActiveRecord::Migration[7.2]
  def change
    create_table :db_links do |t|
      t.references :project, null: false, index: true
      t.references :db_server, null: false, index: true
      t.string :name, limit: 60, null: false
      t.string :schema_name, limit: 128
      t.boolean :production, null: false, default: false
      t.integer :position, null: false, default: 1
      t.timestamps
    end
    add_index :db_links, [:project_id, :name], unique: true
  end
end
