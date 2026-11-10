# 관리 > Jenkins 서버 (관리자 전용)
class JenkinsServersController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :jenkins_servers

  before_action :require_admin
  before_action :find_server, only: [:edit, :update, :destroy, :test]

  def index
    @servers = JenkinsServer.sorted.to_a
  end

  def new
    @server = JenkinsServer.new
  end

  def create
    @server = JenkinsServer.new(server_params)
    if @server.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to jenkins_servers_path
    else
      render :new
    end
  end

  def edit
  end

  def update
    @server.assign_attributes(server_params)
    if @server.save
      flash[:notice] = l(:notice_successful_update)
      redirect_to jenkins_servers_path
    else
      render :edit
    end
  end

  def destroy
    if @server.destroy
      flash[:notice] = l(:notice_successful_delete)
    else
      flash[:error] = l(:error_jenkins_server_in_use)
    end
    redirect_to jenkins_servers_path
  end

  # 저장된 주소·토큰으로 Jenkins 에 접속해 버전과 계정 확인
  def test
    info = @server.client.who_am_i
    if info[:authenticated] && info[:name].present? && info[:name] != 'anonymous'
      flash[:notice] = l(:notice_jenkins_connected, version: info[:version], name: info[:name])
    else
      flash[:error] = l(:error_jenkins_auth)
    end
  rescue JenkinsDeploy::Error => e
    flash[:error] = e.message
  ensure
    redirect_to jenkins_servers_path unless performed?
  end

  private

  def find_server
    @server = JenkinsServer.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def server_params
    params.require(:jenkins_server).permit(:name, :url, :username, :token, :verify_ssl, :timeout)
  end
end
