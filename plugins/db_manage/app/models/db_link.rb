# 프로젝트에서 쓰는 DB (개발DB·운영DB 등) — 관리자가 등록한 DB 서버를 고르고 스키마를 지정
class DbLink < ApplicationRecord
  belongs_to :project
  belongs_to :db_server

  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :project_id }
  validates :schema_name, length: { maximum: 128 }, format: { with: /\A[A-Za-z0-9_$\-]*\z/ }

  scope :sorted, -> { order(:position, :id) }

  # 비워 두면 DB 종류별 기본: PostgreSQL public · SQL Server dbo · Oracle 접속 계정 · MariaDB 는 데이터베이스 이름
  def schema
    return schema_name if schema_name.present?
    DbManage::Connector.default_schema(db_server)
  end

  # 운영 여부는 DB 서버의 개발/운영 구분을 따름 (db_links.production 칸은 005 에서 삭제)
  def production?
    db_server&.production? || false
  end

  def connector
    db_server.connector(schema)
  end

  def to_s
    name
  end
end
