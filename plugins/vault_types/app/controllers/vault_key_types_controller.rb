# 관리 > 접속정보(Vault) > 유형 관리 (관리자 전용)
class VaultKeyTypesController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :vault

  before_action :require_admin
  before_action :find_type, only: [:edit, :update, :destroy]

  def index
    @types = VaultKeyType.sorted.to_a
    @counts = Vault::Key.where(vault_type_id: @types.map(&:id)).group(:vault_type_id).count
  end

  def new
    @type = VaultKeyType.new(position: (VaultKeyType.maximum(:position) || 0) + 1)
  end

  def create
    @type = VaultKeyType.new(type_params)
    if @type.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to vault_key_types_path
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @type.update(type_params)
      # 입력 방식을 바꾸면 이 유형의 접속정보도 같은 방식으로 맞춤
      Vault::Key.where(vault_type_id: @type.id).where.not(type: @type.base_type).update_all(type: @type.base_type) if @type.saved_change_to_base_type?
      flash[:notice] = l(:notice_successful_update)
      redirect_to vault_key_types_path
    else
      render :edit
    end
  end

  def destroy
    if @type.destroy
      flash[:notice] = l(:notice_successful_delete)
    else
      flash[:error] = l(:error_vault_type_in_use)
    end
    redirect_to vault_key_types_path
  end

  private

  def find_type
    @type = VaultKeyType.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def type_params
    params.require(:vault_key_type).permit(:name, :base_type, :position)
  end
end
