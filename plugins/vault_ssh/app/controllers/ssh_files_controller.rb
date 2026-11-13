# 터미널 탭 › 파일 창 — 열려 있는 내 터미널 세션(같은 접속표)으로만, 작업마다 기록
class SshFilesController < ApplicationController
  before_action :require_login
  before_action :find_runner

  def index
    list = @runner.with_sftp { |s| SshConsole::Files.list(s, params[:path]) }
    zone = User.current.time_zone || ActiveSupport::TimeZone['Asia/Seoul']
    list[:entries].each { |e| e[:mtime] = e[:mtime] && Time.at(e[:mtime]).in_time_zone(zone).strftime('%Y-%m-%d %H:%M') }
    render json: { ok: true, prod: @runner.prod ? true : false }.merge(list)
  rescue StandardError => e
    fail_json(e)
  end

  # 받기 — 조금씩 읽어 바로 내려보냄 (큰 로그 파일도 메모리에 다 올리지 않음)
  def download
    path = params[:path].to_s
    st = @runner.with_sftp { |s| SshConsole::Files.stat(s, path) }
    return fail_json(StandardError.new(l(:error_ssh_files_dir))) if st.directory?
    name = File.basename(path)
    log = SshFileLog.create!(ssh_session_id: @session.id, action: 'download', path: path.truncate(500), size: st.size, created_at: Time.current)
    response.headers['Content-Type'] = 'application/octet-stream'
    response.headers['Content-Disposition'] = "attachment; filename=\"#{name.gsub(/[^\w.\-]/, '_')}\"; filename*=UTF-8''#{ERB::Util.url_encode(name)}"
    response.headers['Content-Length'] = st.size.to_s if st.size
    response.headers['Cache-Control'] = 'no-cache'
    response.headers['Last-Modified'] = Time.now.httpdate
    runner = @runner
    self.response_body = Enumerator.new do |y|
      runner.with_sftp { |s| SshConsole::Files.download(s, path) { |d| runner.touch; y << d } }
    rescue StandardError => e
      SshFileLog.where(id: log.id).update_all(ok: false, error: e.message.to_s.truncate(255))
    end
  rescue StandardError => e
    fail_json(e)
  end

  def upload
    dir = params[:dir].to_s
    files = Array(params[:files]).select { |f| f.respond_to?(:read) }
    return fail_json(StandardError.new(l(:error_ssh_files_none))) if files.empty?
    return fail_json(StandardError.new(l(:error_ssh_files_big))) if files.sum(&:size) > SshConsole::Files::MAX_UPLOAD
    done = files.map do |f|
      dest, size = @runner.with_sftp { |s| SshConsole::Files.upload(s, dir, f.original_filename, f) }
      SshFileLog.create!(ssh_session_id: @session.id, action: 'upload', path: dest.truncate(500), size: size, created_at: Time.current)
      dest
    end
    render json: { ok: true, files: done }
  rescue StandardError => e
    log_fail('upload', "#{dir}/#{files&.first&.original_filename}", e)
    fail_json(e)
  end

  def mkdir
    dest = @runner.with_sftp { |s| SshConsole::Files.mkdir(s, params[:dir].to_s, params[:name].to_s.strip) }
    SshFileLog.create!(ssh_session_id: @session.id, action: 'mkdir', path: dest.truncate(500), created_at: Time.current)
    render json: { ok: true, path: dest }
  rescue StandardError => e
    log_fail('mkdir', "#{params[:dir]}/#{params[:name]}", e)
    fail_json(e)
  end

  def rename
    path = params[:path].to_s
    dest = @runner.with_sftp { |s| SshConsole::Files.rename(s, path, params[:name].to_s.strip) }
    SshFileLog.create!(ssh_session_id: @session.id, action: 'rename', path: path.truncate(500), target: dest.truncate(500), created_at: Time.current)
    render json: { ok: true, path: dest }
  rescue StandardError => e
    log_fail('rename', path, e)
    fail_json(e)
  end

  def delete
    path = params[:path].to_s
    @runner.with_sftp { |s| SshConsole::Files.delete(s, path) }
    SshFileLog.create!(ssh_session_id: @session.id, action: 'delete', path: path.truncate(500), created_at: Time.current)
    render json: { ok: true }
  rescue StandardError => e
    log_fail('delete', path, e)
    fail_json(e)
  end

  private

  def find_runner
    @session = SshSession.find_by(ticket: params[:ticket].to_s, user_id: User.current.id)
    @runner = @session && SshConsole::Runner.get(@session.id)
    return fail_json(StandardError.new(l(:error_ssh_files_closed)), 409) unless @runner&.ready?
    @runner.touch
  end

  def log_fail(action, path, err)
    return unless @session
    SshFileLog.create!(ssh_session_id: @session.id, action: action, path: path.to_s.truncate(500), ok: false, error: message(err).truncate(255), created_at: Time.current)
  rescue StandardError
    nil
  end

  def message(err)
    case err
    when SshConsole::TargetError, SshConsole::StepError then err.message
    when ->(e) { defined?(Net::SFTP::StatusException) && e.is_a?(Net::SFTP::StatusException) }
      { 2 => l(:error_ssh_files_nofile), 3 => l(:error_ssh_files_perm), 4 => l(:error_ssh_files_fail) }[err.code] || err.message
    else err.message.to_s
    end
  end

  def fail_json(err, status = 422)
    render json: { ok: false, message: message(err) }, status: status
  end
end
