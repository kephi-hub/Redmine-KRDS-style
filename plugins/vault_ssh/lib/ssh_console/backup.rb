# 프로젝트 시스템 백업 실행
# - DB: SSH 로 운영 서버에서 덤프 명령 실행 → 표준출력을 받으며 PMS 쪽에서 gzip (db_<이름>.sql.gz)
#   DB 비밀번호는 표준입력으로 넘김(운영 서버 ps 에 명령줄로 보이지 않게)
#   Oracle(Data Pump)·SQL Server(BACKUP DATABASE)는 DB 서버에 백업 파일을 만든 뒤 cat 으로 받아 오고 지움
#   (db_<이름>.dmp.gz / .bak.gz) — SSH 서버 = DB 서버, SSH 계정이 그 파일을 읽고 지울 수 있어야 함
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

    MIN_FREE = 1024**3 # 남은 디스크가 1GB 보다 적으면 시작하지 않음 (받는 도중에도 이보다 적어지면 멈춤)
    CHUNK = 256 * 1024
    DISK_CHECK = 64 * 1024**2 # 받는 도중 64MB 마다 남은 디스크 확인
    ERR_KEEP = 8000           # 오류 출력은 마지막 8000 바이트만 (오류는 보통 끝에 나옴)

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
      # 덜 받은 파일은 복원에 쓸 수 없고 디스크만 차지 → 지우고 기록만 남김
      FileUtils.rm_rf(run.path) if run.path && run.path.to_s.start_with?(root.to_s)
      run.update!(status: 'failed', finished_at: Time.current, error: e.message.to_s.truncate(1000), total_bytes: 0)
    end

    def dump_command(job)
      return job.dump_cmd.to_s if job.db_kind == 'custom'
      host = Shellwords.escape(job.db_host.presence || '127.0.0.1')
      name = Shellwords.escape(job.db_name)
      user = Shellwords.escape(job.db_key&.login.to_s)
      port = job.port_or_default.to_i
      case job.db_kind
      when 'mysql'
        # mariadb-dump 만 있는 서버도 있어 둘 중 있는 것. --no-tablespaces: MySQL 8 에서 PROCESS 권한 없는 계정도 덤프되게, --hex-blob: 바이너리 칸을 16진수로(문자셋 변환에 깨지지 않게)
        "IFS= read -r P; export MYSQL_PWD=\"$P\"; D=$(command -v mariadb-dump || command -v mysqldump); " \
          "[ -n \"$D\" ] || { echo 'mariadb-dump/mysqldump 를 찾을 수 없습니다 (SSH 서버에 DB 클라이언트 설치 필요)' >&2; exit 127; }; " \
          "exec $D --single-transaction --quick --routines --triggers --events --no-tablespaces --hex-blob --default-character-set=utf8mb4 -h #{host} -P #{port} -u #{user} #{name}"
      when 'postgresql'
        # --clean --if-exists: 이미 있는 DB 에 그대로 복원해도 겹치지 않게 (지우고 다시 만듦)
        "IFS= read -r P; export PGPASSWORD=\"$P\"; exec pg_dump --no-owner --no-privileges --clean --if-exists -h #{host} -p #{port} -U #{user} #{name}"
      when 'oracle' then oracle_command(job, host, port)
      when 'mssql' then mssql_command(job, host, port)
      end
    end

    # Oracle — Data Pump 로 DB 계정의 스키마를 DATA_PUMP_DIR 에 내보낸 뒤 cat, 끝나면 지움
    # 비밀번호는 sqlplus(/nolog + connect)·expdp(Username 질문)에 표준입력으로 넘김(명령줄·환경변수에 안 남음)
    # 비대화 SSH 는 oracle 환경이 안 잡히는 경우가 많아 프로필을 읽고 ORACLE_HOME/bin 을 PATH 에 더함
    def oracle_command(job, host, port)
      login = job.db_key&.login.to_s
      raise I18n.t(:error_sb_db_login) unless login.match?(/\A[A-Za-z][\w$#]*\z/)
      tns = Shellwords.escape("//#{job.db_host.presence || '127.0.0.1'}:#{port}/#{job.db_name}")
      <<~SH
        IFS= read -r P
        for f in "$HOME/.bash_profile" "$HOME/.profile"; do [ -f "$f" ] && . "$f" >/dev/null 2>&1; done
        [ -n "$ORACLE_HOME" ] && PATH="$ORACLE_HOME/bin:$PATH"
        command -v expdp >/dev/null 2>&1 || { echo "expdp/sqlplus 를 찾을 수 없습니다 (SSH 계정의 ORACLE_HOME·PATH 확인)" >&2; exit 127; }
        case "$P" in *'"'*) echo 'DB 비밀번호에 큰따옴표(")가 있으면 Oracle 백업을 할 수 없습니다' >&2; exit 2;; esac
        T=#{tns}
        O=$(printf 'connect #{login}/"%s"@%s\\nset heading off feedback off pagesize 0 verify off\\nselect directory_path from all_directories where directory_name = %s;\\nexit\\n' "$P" "$T" "'DATA_PUMP_DIR'" | sqlplus -s /nolog 2>&1 | tr -d '\\r')
        DP=$(printf '%s\\n' "$O" | grep '^/' | head -1); DP=${DP%/}
        [ -n "$DP" ] || { printf '%s\\n' "$O" | grep -E 'ORA-|SP2-' | head -2 >&2; echo "DATA_PUMP_DIR 경로를 읽지 못했습니다 — 위 오류(ORA-01017 = 계정·비밀번호) 또는 GRANT READ, WRITE ON DIRECTORY DATA_PUMP_DIR 권한 확인" >&2; exit 2; }
        F="pms_bk_$$_$(date +%Y%m%d%H%M%S)"
        trap 'rm -f "$DP/$F.dmp" "$DP/$F.log"' EXIT
        # 계정을 명령줄에 쓰지 않으면 expdp 가 Username 을 물음 → 계정/"비밀번호"@접속 을 표준입력으로 답함
        printf '#{login}/"%s"@%s\\n' "$P" "$T" | expdp schemas=#{login} directory=DATA_PUMP_DIR dumpfile="$F.dmp" logfile="$F.log" >&2 || { E=$?; echo "expdp 실패 (종료 코드 $E)" >&2; exit 3; }
        [ -r "$DP/$F.dmp" ] || { echo "덤프 파일을 읽을 수 없습니다: $DP/$F.dmp (SSH 계정을 oracle 또는 oinstall 그룹으로)" >&2; exit 4; }
        cat "$DP/$F.dmp"
      SH
    end

    # SQL Server(Linux) — 기본 백업 폴더에 COPY_ONLY 백업(기존 백업 체인을 건드리지 않음) 뒤 cat, 끝나면 지움
    # 비밀번호는 SQLCMDPASSWORD 환경변수(명령줄에 안 보임). sqlcmd 18 은 암호화 기본이라 -C(인증서 신뢰)
    def mssql_command(job, host, port)
      dbq = job.db_name.to_s.gsub(']', ']]')
      server = Shellwords.escape("#{job.db_host.presence || '127.0.0.1'},#{port}")
      user = Shellwords.escape(job.db_key&.login.to_s)
      <<~SH
        IFS= read -r P; export SQLCMDPASSWORD="$P"
        S=$(command -v sqlcmd || ls /opt/mssql-tools18/bin/sqlcmd /opt/mssql-tools/bin/sqlcmd 2>/dev/null | head -1)
        [ -n "$S" ] || { echo "sqlcmd 를 찾을 수 없습니다 (mssql-tools 설치 확인)" >&2; exit 127; }
        O=""; "$S" -? 2>&1 | grep -q -- '-C' && O="-C"
        B=$("$S" -S #{server} -U #{user} $O -b -h -1 -W -Q "SET NOCOUNT ON; SELECT CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(4000))" | tr -d '\\r' | grep '^/' | head -1)
        B=${B%/}; B=${B:-/var/opt/mssql/data}
        F="$B/pms_bk_$$_$(date +%Y%m%d%H%M%S).bak"
        trap 'rm -f "$F"' EXIT
        "$S" -S #{server} -U #{user} $O -b -Q "BACKUP DATABASE [#{dbq}] TO DISK = N'$F' WITH COPY_ONLY, INIT, CHECKSUM" >&2 || { E=$?; echo "BACKUP DATABASE 실패 (종료 코드 $E)" >&2; exit 3; }
        [ -r "$F" ] || { echo "백업 파일을 읽을 수 없습니다: $F (SSH 계정을 mssql 그룹 또는 root 로)" >&2; exit 4; }
        cat "$F"
      SH
    end

    # DB 덤프 → db_<이름>.sql.gz
    def dump_db(job, dir)
      key = job.ssh_key or raise I18n.t(:error_sb_no_ssh)
      file = dir.join("db_#{(job.db_name.presence || job.name).gsub(/[^\w.-]/, '_')}.#{job.dump_ext}.gz")
      secret = job.db_kind == 'custom' ? nil : Target.secret(job.db_key || raise(I18n.t(:error_sb_no_dbkey)))
      bytes = 0
      checked = 0
      err = +''
      status = nil
      Zlib::GzipWriter.open(file.to_s) do |gz|
        Exec.stream(key, dump_command(job), stdin: (secret.nil? ? nil : "#{secret}\n")) do |kind, data|
          if kind == :out
            gz.write(data)
            bytes += data.bytesize
            if bytes - checked >= DISK_CHECK
              checked = bytes
              free = disk[:free]
              raise I18n.t(:error_sb_disk) if free.positive? && free < MIN_FREE
            end
          elsif kind == :err
            err << data
            err = err.byteslice(-ERR_KEEP, ERR_KEEP) if err.bytesize > ERR_KEEP * 2
          else
            status = data
          end
        end
      end
      raise I18n.t(:error_sb_dump, code: status, msg: err_tail(err)) unless status.to_i.zero?
      raise I18n.t(:error_sb_empty) if bytes.zero?
      { bytes: bytes, files_total: 1, files_new: 1 }
    end

    # 오류 출력의 마지막 3줄(빈 줄 제외)을 400자 안으로 — 실제 오류는 보통 끝에 있으므로 길면 앞을 자름
    def err_tail(err)
      msg = err.to_s.scrub.lines.map(&:strip).reject(&:empty?).last(3).join(' ')
      msg.length > 400 ? "…#{msg[-399..]}" : msg
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

    # [덤프 받기] 파일 이름 — <프로젝트>_<날짜>_db_<이름>.sql.gz
    def download_name(run)
      file = dump_file(run)
      file && "#{run.sys_backup_job.project.identifier}_#{File.basename(run.dir)}_#{File.basename(file)}"
    end

    # 보관된 DB 덤프 파일 (db_*.sql.gz / .dmp.gz / .bak.gz)
    def dump_file(run)
      run.path && Dir[run.path.join('db_*.gz').to_s].first
    end

    # 복원 안내 명령 (화면 표시용, 비밀번호 없음)
    def restore_hint(job, run)
      return nil unless run.path
      if job.db?
        rel = download_name(run)
        h = job.db_host.presence || '127.0.0.1'
        u = job.db_key&.login
        case job.db_kind
        when 'mysql' then "gunzip -c #{rel} | mysql -h #{h} -P #{job.port_or_default} -u #{u} -p #{job.db_name}"
        when 'postgresql' then "gunzip -c #{rel} | psql -h #{h} -p #{job.port_or_default} -U #{u} #{job.db_name}"
        when 'oracle'
          dmp = rel.to_s.delete_suffix('.gz')
          "gunzip -c #{rel} > <DATA_PUMP_DIR 경로>/#{dmp}   # oracle 계정으로\n" \
            "impdp #{u}@//#{h}:#{job.port_or_default}/#{job.db_name} directory=DATA_PUMP_DIR dumpfile=#{dmp} schemas=#{u} table_exists_action=replace"
        when 'mssql'
          bak = rel.to_s.delete_suffix('.gz')
          "gunzip -c #{rel} > /var/opt/mssql/backup/#{bak} && chown mssql: /var/opt/mssql/backup/#{bak}\n" \
            "sqlcmd -S #{h},#{job.port_or_default} -U #{u} -C -Q \"RESTORE DATABASE [#{job.db_name}] FROM DISK = N'/var/opt/mssql/backup/#{bak}' WITH REPLACE\""
        else "gunzip -c #{rel}"
        end
      else
        "rsync -a backup/sys/#{run.dir}/files/ <운영 서버>:/   # 예) 폴더 하나만: backup/sys/#{run.dir}/files#{job.path_list.first}/"
      end
    end
  end
end
