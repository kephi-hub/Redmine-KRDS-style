# 터미널 파일 창 작업 한 줄 (접속 기록에 딸림)
class SshFileLog < ApplicationRecord
  ACTIONS = %w(download upload mkdir rename delete).freeze
  belongs_to :ssh_session
  validates :action, inclusion: { in: ACTIONS }
end
