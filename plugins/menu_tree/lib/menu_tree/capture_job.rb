# 화면 [지금 캡처] — 백그라운드(같은 프로세스의 ActiveJob)
module MenuTree
  class CaptureJob < ActiveJob::Base
    queue_as :default

    def perform(run_id)
      run = MenuCaptureRun.find_by(id: run_id)
      Capture.run!(run) if run&.status == 'queued'
    end
  end
end
