class OpsAssetLink < ApplicationRecord
  belongs_to :ops_asset
  belongs_to :project
end
