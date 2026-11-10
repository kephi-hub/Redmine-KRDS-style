class CreateDeployRuns < ActiveRecord::Migration[7.2]
  def change
    create_table :deploy_runs do |t|
      t.integer :project_id, null: false
      t.integer :deploy_target_id
      t.integer :user_id
      t.string :target_name, limit: 60
      t.string :job_path, limit: 255
      t.boolean :production, null: false, default: false
      t.text :params
      t.string :note, limit: 255
      t.integer :queue_id
      t.integer :build_number
      t.string :status, limit: 20, null: false, default: 'queued'
      t.string :error_message, limit: 255
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :deploy_runs, [:project_id, :id]
    add_index :deploy_runs, [:deploy_target_id, :status]
  end
end
