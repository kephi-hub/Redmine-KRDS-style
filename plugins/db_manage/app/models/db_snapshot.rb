# DB 구조 저장본 (변경 이력). data 는 gzip 으로 압축한 JSON — 행 수·읽은 시각처럼 늘 바뀌는 값은 빼고 저장
# summary: 바로 앞 저장본과 비교한 요약 { only_a:, only_b:, changed:, objects: } (처음이면 nil)
require 'zlib'

class DbSnapshot < ApplicationRecord
  KEEP = 100

  belongs_to :db_link
  belongs_to :user, optional: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  # 지금 구조를 읽어 바뀌었으면 저장 → [:saved | :same, 저장본]
  def self.capture(link, user = nil)
    snap = link.connector.snapshot(objects: true)
    payload = normalize(snap)
    json = payload.to_json
    digest = Digest::SHA256.hexdigest(json)
    last = where(db_link_id: link.id).recent.first
    return [:same, last] if last && last.digest == digest
    summary = nil
    if last
      before = last.structure
      result = DbManage::Analysis.compare(before, payload_to_structure(payload))
      objects = DbManage::Analysis.compare_objects(before, payload_to_structure(payload), link.schema, link.schema)
      summary = { only_a: result[:only_a].size, only_b: result[:only_b].size, changed: result[:changed].size,
                  objects: objects.sum { |g| g[:rows].size } }
    end
    rec = create!(db_link: link, user: user, digest: digest, data: Zlib::Deflate.deflate(json),
                  table_count: payload[:tables].size, column_count: payload[:columns].sum { |_, c| c.size },
                  object_count: payload[:objects].values.compact.sum(&:size), summary: summary&.to_json, created_at: Time.now)
    where(db_link_id: link.id).recent.offset(KEEP).destroy_all
    [:saved, rec]
  end

  # 저장용: 이름을 키로 쓰는 해시는 [이름, 값] 배열로 (JSON 왕복 때 키가 바뀌지 않게)
  def self.normalize(snap)
    { tables: snap[:tables].map { |t| t.except(:rows) },
      columns: snap[:columns].sort.map { |t, cols| [t, cols] },
      indexes: snap[:indexes].to_h.sort.map { |t, l| [t, l] },
      objects: snap[:objects] || {}, kinds: snap[:kinds], flavor: snap[:flavor], schema: snap[:schema] }
  end

  def self.payload_to_structure(p)
    sym = ->(h) { h.to_h.transform_keys(&:to_sym) }
    { tables: p[:tables].map { |t| sym.call(t) },
      columns: p[:columns].to_h { |t, cols| [t, cols.map { |c| sym.call(c) }] },
      indexes: p[:indexes].to_h { |t, l| [t, l.map { |i| sym.call(i) }] },
      objects: p[:objects].to_h { |k, l| [k.to_s, l&.map { |o| sym.call(o) }] },
      kinds: p[:kinds], flavor: p[:flavor], schema: p[:schema] }
  end

  # 화면·비교용 구조 (Connector#snapshot 과 같은 모양)
  def structure
    @structure ||= self.class.payload_to_structure(JSON.parse(Zlib::Inflate.inflate(data), symbolize_names: false).then do |d|
      { tables: d['tables'], columns: d['columns'], indexes: d['indexes'], objects: d['objects'], kinds: d['kinds'], flavor: d['flavor'], schema: d['schema'] }
    end)
  end

  def summary_hash
    summary.present? ? JSON.parse(summary, symbolize_names: true) : nil
  end

  def changed?
    s = summary_hash
    s && (s[:only_a] + s[:only_b] + s[:changed] + s[:objects]).positive?
  end
end
