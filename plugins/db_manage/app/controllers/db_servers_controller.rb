# 관리 > DB 서버 (관리자 전용) — Jenkins 서버 관리와 같은 방식
class DbServersController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :db_servers

  before_action :require_admin
  before_action :find_server, only: [:edit, :update, :destroy, :test]

  def index
    @servers = DbServer.sorted.includes(db_links: :project).to_a
  end

  def new
    @server = DbServer.new(adapter: 'mariadb', port: 3306, timeout: 10)
  end

  def create
    @server = DbServer.new(server_params)
    if @server.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to db_servers_path
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
      redirect_to db_servers_path
    else
      render :edit
    end
  end

  def destroy
    if @server.destroy
      flash[:notice] = l(:notice_successful_delete)
    else
      flash[:error] = l(:error_db_server_in_use)
    end
    redirect_to db_servers_path
  end

  # 저장된 접속정보로 접속해 DB 버전 확인
  def test
    flash[:notice] = l(:notice_db_connected, name: @server.name, version: @server.connector.version)
  rescue DbManage::Error => e
    flash[:error] = "#{@server.name}: #{e.message}"
  ensure
    redirect_to db_servers_path unless performed?
  end

  private

  def find_server
    @server = DbServer.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def server_params
    params.require(:db_server).permit(:name, :adapter, :host, :port, :database_name, :username, :password, :timeout, :note)
  end
end
