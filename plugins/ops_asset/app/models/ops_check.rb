# 정기점검 한 회 — results: [{ 'item' =>, 'result' => ok|issue|na, 'action' => }] (JSON)
class OpsCheck < ApplicationRecord
  RESULTS = %w(ok issue na).freeze

  belongs_to :project
  belongs_to :ops_check_template, optional: true
  belongs_to :user, optional: true

  validates :name, presence: true, length: { maximum: 120 }
  validates :checked_on, presence: true

  scope :sorted, -> { order(checked_on: :desc, id: :desc) }

  def result_list
    JSON.parse(results.to_s).select { |r| r.is_a?(Hash) }
  rescue JSON::ParserError
    []
  end

  def result_list=(list)
    self.results = Array(list).map { |r| r.slice('item', 'result', 'action') }.to_json
  end

  def counts
    result_list.group_by { |r| r['result'] }.transform_values(&:size)
  end

  def issue_count
    counts['issue'].to_i
  end
end
