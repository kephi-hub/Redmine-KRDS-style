# 화면 캡처 설정 — 사이트별(사이트가 없으면 프로젝트에 하나). 로그인 비밀번호는 Redmine 암호화 키로 암호화 저장
class MenuCaptureConfig < ApplicationRecord
  SCHEDULES = %w(off daily weekly).freeze
  # 로그인 입력칸을 못 정하면 차례로 찾아봄
  USER_SELECTORS = 'input[name=username], input[name=userId], input[name=user_id], input[name=loginId], input[name=login_id], input[name=id], input[name=email], input[type=email], input[name=login], #username, #userId, #loginId, #id, input[type=text]'
  PASS_SELECTORS = 'input[type=password]'
  SUBMIT_SELECTORS = 'button[type=submit], input[type=submit], button.btn_login, .btn-login, #loginBtn, #btnLogin, button'

  belongs_to :project
  belongs_to :menu_site, optional: true
  has_many :menu_capture_runs, dependent: :nullify

  validates :base_url, :login_url, format: { with: %r{\Ahttps?://[^\s]+\z}i }, allow_blank: true, length: { maximum: 300 }
  validates :base_url, presence: true
  validates :username, length: { maximum: 100 }
  validates :user_selector, :pass_selector, :submit_selector, :check_selector, length: { maximum: 200 }
  validates :width, numericality: { only_integer: true, greater_than_or_equal_to: 320, less_than_or_equal_to: 2560 }
  validates :wait_ms, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 30_000 }
  validates :max_height, numericality: { only_integer: true, greater_than_or_equal_to: 1000, less_than_or_equal_to: 30_000 }
  validates :keep, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 100 }
  validates :schedule, inclusion: { in: SCHEDULES }

  before_validation do
    self.base_url = base_url.to_s.strip.sub(%r{/+\z}, '').presence
    self.login_url = login_url.to_s.strip.presence
    self.username = username.to_s.strip.presence
  end

  def password
    Redmine::Ciphering.decrypt_text(password_enc)
  end

  def password=(value)
    self.password_enc = Redmine::Ciphering.encrypt_text(value.to_s) if value.present?
  end

  def login?
    login_url.present? && username.present? && password_enc.present?
  end

  # 메뉴 URL → 캡처할 주소 (절대 주소면 그대로, /로 시작하면 기본 주소의 호스트 뒤, 아니면 기본 주소 뒤)
  def resolve(url)
    u = url.to_s.strip
    return nil if u.blank? || u.start_with?('javascript:', '#')
    return u if u =~ %r{\Ahttps?://}i
    base = URI.parse(base_url) rescue nil
    return nil unless base
    if u.start_with?('/')
      "#{base.scheme}://#{base.host}#{":#{base.port}" unless [80, 443].include?(base.port)}#{u}"
    else
      "#{base_url}/#{u}"
    end
  end

  def label
    menu_site ? menu_site.name : project.name
  end

  # 예약: 매일 · 매주(월요일)
  def due?(date = Date.current)
    schedule == 'daily' || (schedule == 'weekly' && date.monday?)
  end
end
