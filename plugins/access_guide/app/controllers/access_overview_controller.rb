# 이전 주소 /access_overview — 권한 한눈에 보기는 역할 및 권한 > 권한 설정 화면으로 합쳐짐 (access_guide 1.3.0)
class AccessOverviewController < ApplicationController
  before_action :require_admin

  def index
    redirect_to permissions_roles_path
  end
end
