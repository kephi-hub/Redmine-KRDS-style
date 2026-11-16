# 시스템 백업 화면용 문구
module SshConsole
  module BackupView
    module_function

    # 진행 표시용 값 — 진행률은 직전 완료본과 비교(DB: 받은 바이트, 폴더: 파일 수). 직전 완료본이 없으면 nil(흐르는 막대)
    def live(run)
      job = run.sys_backup_job
      prev = job.sys_backup_runs.where(status: 'done').where.not(id: run.id).first
      cur, ref = job.db? ? [run.bytes.to_i, prev&.bytes.to_i] : [run.files_total.to_i, prev&.files_total.to_i]
      pct = ref.to_i.positive? ? [cur * 100 / ref, 99].min : nil
      { id: run.id, status: run.status, active: run.busy?, start: run.started_at&.to_i, seconds: run.seconds,
        bytes: run.bytes.to_i, files_total: run.files_total.to_i, files_new: run.files_new.to_i, files_linked: run.files_linked.to_i,
        files: job.files?, pct: pct, est: (prev&.seconds) }
    end

    def schedule_text(job)
      return I18n.t(:label_sb_sch_off) if job.schedule == 'off' || !job.active
      at = format('%02d:00', job.hour)
      if job.schedule == 'weekly'
        I18n.t(:label_sb_when_weekly, day: I18n.t(:label_sb_weekday)[job.weekday - 1], at: at)
      else
        I18n.t(:label_sb_when_daily, at: at)
      end
    end
  end
end
