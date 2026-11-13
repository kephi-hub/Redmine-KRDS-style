# 프로젝트 시스템 백업 실행
# - DB: SSH 로 운영 서버에서 덤프 명령 실행 → 표준출력을 받으며 PMS 쪽에서 gzip (db_<이름>.sql.gz)
#   DB 비밀번호는 표준입력으로 넘김(운영 서버 ps 에 명령줄로 보이지 않게)
# - 폴더: SFTP 로 받되 지난 보관본과 크기·수정 시각이 같으면 받지 않고 하드링크 (변경분만 받기)
# - 보관: SYS_BACKUP_DIR(기본 <redmine>/sys_backups — 호스트 backup/sys 마운트)/<프로젝트>/<작업>/<YYYYmmdd_HHMMSS>/
#   작업마다 보관 횟수만큼 남기고 오래된 것부터 지움
require 'zlib'
require 'json'
require 'shellwords'
require 'fileutils'

module SshConsole
  module Backup
    module_function

    MIN_FREE = 1024**3 # 남은 디스크가 1GB 보다 적으면 시작하지 않음
    CHUNK = 256 * 1024

    def root
      Pathname.new(ENV['SYS_BACKUP_DIR'].presence || Rails.root.join('sys_backups').to_s)
    end

    def ready?
      FileUtils.mkdir_p(root)
      File.writable?(root)
    rescue StandardError
      false
    end

    def disk
      out = `df -Pk #{Shellwords.escape(root.to_s)} 2>/dev/null`.lines.last.to_s.split
      { total: out[1].to_i * 1024, free: out[3].to_i * 1024 }
    rescue StandardError
      { total: 0, free: 0 }
    end

    def used(path = root)
      `du -sk #{Shellwords.escape(path.to_s)} 2>/dev/null`.split.first.to_i * 1024
    rescue StandardError
      0
    end

    # 실행 (BackupJob · rake 에서) — run 은 queued 상태로 만들어 둔 SysBackupRun
    def run!(run)
      job = run.sys_backup_job
      run.update!(status: 'running', started_at: Time.current)
      job.update_columns(last_run_at: Time.current)
      raise I18n.t(:error_sb_dir) unless ready?
      raise I18n.t(:error_sb_disk) if disk[:free].positive? && disk[:free] < MIN_FREE
      dir = "#{job.project_id}/#{job.id}/#{Time.current.in_time_zone('Asia/Seoul').strftime('%Y%m%d_%H%M%S')}"
      FileUtils.mkdir_p(root.join(dir))
      run.update_columns(dir: dir)
      ActiveRecord::Base.connection_pool.release_connection
      stats = job.db? ? dump_db(job, root.join(dir)) : mirror(job, run, root.join(dir))
      run.update!(stats.merge(status: 'done', finished_at: Time.current, total_bytes: used(root.join(dir))))
      prune(job)
    rescue StandardError => e
      Rails.logger.error("[sys_backup] job #{run.sys_backup_job_id}: #{e.class} #{e.message}")
      run.update!(status: 'failed', finished_at: Time.current, error: e.message.to_s.truncate(1000))
    end

    def dump_command(job)
      return job.dump_cmd.to_s if job.db_kind == 'custom'
      host = Shellwords.escape(job.db_host.presence || '127.0.0.1')
      name = Shellwords.escape(job.db_name)
      user = Shellwords.escape(job.db_key&.login.to_s)
      case job.db_kind
      when 'mysql'
        port = job.db_port || 3306
        # mariadb-dump 만 있는 서버도 있어 둘 중 있는 것
        "IFS= read -r P; export MYSQL_PWD=\"$P\"; D=$(command -v mysqldump || command -v mariadb-dump); " \
          "exec $D --single-transaction --quick --routines --triggers --events --default-character-set=utf8mb4 -h #{host} -P #{port} -u #{user} #{name}"
      when 'postgresql'
        port = job.db_port || 5432
        "IFS= read -r P; export PGPASSWORD=\"$P\"; exec pg_dump --no-owner --no-privileges -h #{host} -p #{port} -U #{user} #{name}"
      end
    end

    # DB 덤프 → db_<이름>.sql.gz
    def dump_db(job, dir)
      key = job.ssh_key or raise I18n.t(:error_sb_no_ssh)
      file = dir.join("db_#{(job.db_name.presence || job.name).gsub(/[^\w.-]/, '_')}.sql.gz")
      secret = job.db_kind == 'custom' ? nil : Target.secret(job.db_key || raise(I18n.t(:error_sb_no_dbkey)))
      bytes = 0
      err = +''
      status = nil
      Zlib::GzipWriter.open(file.to_s) do |gz|
        Exec.stream(key, dump_command(job), stdin: (secret.nil? ? nil : "#{secret}\n")) do |kind, data|
          if kind == :out
            gz.write(data)
            bytes += data.bytesize
          elsif kind == :err
            err << data if err.bytesize < 8000
          else
            status = data
          end
        end
      end
      raise I18n.t(:error_sb_dump, code: status, msg: err.strip.lines.last(3).join(' ').truncate(400)) unless status.to_i.zero?
      raise I18n.t(:error_sb_empty) if bytes.zero?
      { bytes: bytes, files_total: 1, files_new: 1 }
    end

    def excluded?(rel, name, patterns)
      patterns.any? do |pt|
        File.fnmatch?(pt, rel, File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_EXTGLOB) ||
          File.fnmatch?(pt, name, File::FNM_DOTMATCH | File::FNM_EXTGLOB) ||
          (pt.end_with?('/') && (rel + '/').start_with?(pt.sub(%r{\A/}, '')))
      end
    end

    # 폴더 → files/<폴더 경로>/…, manifest.json.gz(경로 → [크기, 수정 시각])
    def mirror(job, run, dir)
      key = job.ssh_key or raise I18n.t(:error_sb_no_ssh)
      prev = job.sys_backup_runs.where(status: 'done').where.not(id: run.id).first
      prev_dir = prev&.path
      prev_man = load_manifest(prev_dir)
      man = {}
      st = { bytes: 0, files_total: 0, files_new: 0, files_linked: 0 }
      patterns = job.exclude_list
      Exec.sftp(key) do |sftp|
        job.path_list.each do |base|
          base = base.chomp('/')
          walk(sftp, base, '') do |rel, attrs|
            full_rel = File.join(base.sub(%r{\A/}, ''), rel)
            next if excluded?(rel, File.basename(rel), patterns)
            dest = dir.join('files', full_rel)
            FileUtils.mkdir_p(dest.dirname)
            size, mtime = attrs.size.to_i, attrs.mtime.to_i
            man[full_rel] = [size, mtime]
            st[:files_total] += 1
            old = prev_man[full_rel]
            src = prev_dir&.join('files', full_rel)
            if old == [size, mtime] && src && File.file?(src)
              File.link(src, dest)
              st[:files_linked] += 1
            else
              left = size
              File.open(dest, 'wb') do |out|
                sftp.file.open(File.join(base, rel), 'r') do |f|
                  while left.positive?
                    data = f.read([CHUNK, left].min)
                    break if data.nil? || data.empty?
                    out.write(data)
                    left -= data.bytesize
                  end
                end
              end
              File.utime(mtime, mtime, dest) if mtime.positive?
              st[:bytes] += size
              st[:files_new] += 1
            end
          end
        end
      end
      Zlib::GzipWriter.open(dir.join('manifest.json.gz').to_s) { |gz| gz.write(man.to_json) }
      st
    end

    # 폴더를 돌며 파일마다 (상대 경로, 속성) — 심볼릭 링크는 따라가지 않음
    def walk(sftp, base, rel, &block)
      path = rel.empty? ? base : File.join(base, rel)
      sftp.dir.foreach(path) do |e|
        next if %w(. ..).include?(e.name)
        a = e.attributes
        r = rel.empty? ? e.name : File.join(rel, e.name)
        if a.directory?
          walk(sftp, base, r, &block)
        elsif a.file?
          yield r.dup.force_encoding('UTF-8'), a
        end
      end
    end

    def load_manifest(dir)
      return {} unless dir && File.file?(dir.join('manifest.json.gz'))
      JSON.parse(Zlib::GzipReader.open(dir.join('manifest.json.gz').to_s, &:read))
    rescue StandardError
      {}
    end

    # 보관 횟수 넘는 완료본 · 오래된 실패 기록 정리
    def prune(job)
      done = job.sys_backup_runs.where(status: 'done').order(id: :desc).to_a
      done.drop(job.keep).each(&:destroy)
      job.sys_backup_runs.where(status: 'failed').where('created_at < ?', 60.days.ago).each(&:destroy)
    end

    # 복원 안내 명령 (화면 표시용, 비밀번호 없음)
    def restore_hint(job, run)
      return nil unless run.path
      if job.db?
        file = Dir[run.path.join('*.sql.gz').to_s].first
        rel = file && Pathname.new(file).relative_path_from(root).to_s
        case job.db_kind
        when 'mysql' then "gunzip -c backup/sys/#{rel} | mysql -h #{job.db_host.presence || '127.0.0.1'} -P #{job.db_port || 3306} -u #{job.db_key&.login} -p #{job.db_name}"
        when 'postgresql' then "gunzip -c backup/sys/#{rel} | psql -h #{job.db_host.presence || '127.0.0.1'} -p #{job.db_port || 5432} -U #{job.db_key&.login} #{job.db_name}"
        else "gunzip -c backup/sys/#{rel}"
        end
      else
        "rsync -a backup/sys/#{run.dir}/files/ <운영 서버>:/   # 예) 폴더 하나만: backup/sys/#{run.dir}/files#{job.path_list.first}/"
      end
    end
  end
end
