# DB 이관 실행 — 백그라운드(같은 프로세스의 ActiveJob)
module DbManage
  class MigrateJob < ActiveJob::Base
    queue_as :default

    def perform(id)
      mig = DbMigration.find_by(id: id)
      Migrator.run!(mig) if mig&.status == 'queued'
    end
  end
end
