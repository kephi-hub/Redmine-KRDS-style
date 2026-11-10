class CreateDeployTargets < ActiveRecord::Migration[7.2]
  def change
    create_table :deploy_targets do |t|
      t.integer :project_id, null: false
      t.integer :jenkins_server_id, null: false
      t.string :name, limit: 60, null: false
      t.string :job_path, limit: 255, null: false
      t.boolean :production, null: false, default: false
      t.text :default_params
      t.timestamps
    end
    add_index :deploy_targets, :project_id
    add_index :deploy_targets, :jenkins_server_id
  end
end
