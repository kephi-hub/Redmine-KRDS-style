class CreateJenkinsServers < ActiveRecord::Migration[7.2]
  def change
    create_table :jenkins_servers do |t|
      t.string :name, limit: 60, null: false
      t.string :url, limit: 255, null: false
      t.string :username, limit: 120, null: false
      t.text :token_encrypted
      t.boolean :verify_ssl, null: false, default: true
      t.integer :timeout, null: false, default: 10
      t.timestamps
    end
    add_index :jenkins_servers, :name, unique: true
  end
end
