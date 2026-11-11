class CreateDbServers < ActiveRecord::Migration[7.2]
  def change
    create_table :db_servers do |t|
      t.string :name, limit: 60, null: false
      t.string :adapter, limit: 20, null: false
      t.string :host, limit: 255, null: false
      t.integer :port, null: false
      t.string :database_name, limit: 128, null: false
      t.string :username, limit: 120, null: false
      t.text :password_encrypted
      t.integer :timeout, null: false, default: 10
      t.string :note, limit: 255
      t.timestamps
    end
    add_index :db_servers, :name, unique: true
  end
end
