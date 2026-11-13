# 시스템 백업 화면용 문구
module SshConsole
  module BackupView
    module_function

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
