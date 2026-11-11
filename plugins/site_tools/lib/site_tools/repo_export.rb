# 소스코드 다운로드 — SVN 은 svn export, Git 은 git archive 로 받은 뒤 zip 으로 묶음
# - 지금 보고 있는 폴더(경로)·리비전 기준, 저장소에 저장된 계정으로 접속(비대화형, 인증 정보 캐시 안 함)
# - 동시에 하나만(서버 부하), 시간 제한 10분, 크기 제한 2GB, 링크 파일은 뺌
# - 만든 zip 은 tmp/repo_exports 에 두었다가 1시간 지나면 다음 다운로드 때 지움
require 'open3'
require 'zip'
require 'securerandom'

module SiteTools
  module RepoExport
    class Error < StandardError; end

    LOCK = Mutex.new
    TIMEOUT = 600
    MAX_BYTES = 2 * 1024**3

    module_function

    def dir
      d = Rails.root.join('tmp', 'repo_exports')
      FileUtils.mkdir_p(d)
      d
    end

    def supported?(repository)
      repository.is_a?(Repository::Subversion) || repository.is_a?(Repository::Git)
    end

    def cleanup
      Dir.glob(dir.join('*')).each do |f|
        FileUtils.rm_rf(f) if File.mtime(f) < 1.hour.ago
      end
    end

    def clean_path(path)
      parts = path.to_s.split('/').reject { |s| s.empty? || s == '.' }
      raise Error, '경로가 올바르지 않습니다.' if parts.include?('..')
      parts.join('/')
    end

    # 반환: [zip 경로, 내려받을 파일 이름, 파일 수, 원본 바이트]
    def build(repository, path, rev)
      raise Error, I18n.t(:error_repo_export_type) unless supported?(repository)
      raise Error, I18n.t(:error_repo_export_busy) unless LOCK.try_lock
      begin
        cleanup
        path = clean_path(path)
        work = dir.join(SecureRandom.hex(8))
        FileUtils.mkdir_p(work)
        base = [repository.project.identifier, repository.identifier.presence, path.split('/').last].compact.join('_')
        if repository.is_a?(Repository::Git)
          rev = git_rev(rev)
          zip = work.join('out.zip')
          args = ['git', "--git-dir=#{repository.url}", 'archive', '--format=zip', "--prefix=#{base}/", '-o', zip.to_s, rev]
          args += ['--', path] if path.present?
          run(args)
          size = File.size(zip)
          raise Error, I18n.t(:error_repo_export_large) if size > MAX_BYTES
          return [zip.to_s, "#{base}_#{rev.tr('/', '_')}.zip", nil, size]
        end
        rev = svn_rev(rev)
        url = repository.url.chomp('/')
        url += '/' + path.split('/').map { |s| ERB::Util.url_encode(s) }.join('/') if path.present?
        target = work.join(base)
        args = ['svn', 'export', '--non-interactive', '--no-auth-cache', '--quiet', '-r', rev]
        args += ['--username', repository.login] if repository.login.present?
        args += ['--password', repository.password] if repository.login.present? && repository.password.present?
        args += ["#{url}@#{rev}", target.to_s]
        run(args)
        files = []
        bytes = 0
        if File.file?(target)
          files << [target.to_s, File.basename(target)]
          bytes = File.size(target)
        else
          Dir.glob(File.join(target, '**', '*'), File::FNM_DOTMATCH).sort.each do |f|
            next if File.symlink?(f) || !File.file?(f)
            files << [f, "#{base}/#{f.delete_prefix("#{target}/")}"]
            bytes += File.size(f)
            raise Error, I18n.t(:error_repo_export_large) if bytes > MAX_BYTES
          end
        end
        zip = work.join('out.zip')
        Zip::OutputStream.open(zip.to_s) do |zos|
          files.each do |f, name|
            zos.put_next_entry(name)
            File.open(f, 'rb') { |io| IO.copy_stream(io, zos) }
          end
        end
        FileUtils.rm_rf(target)
        [zip.to_s, "#{base}_r#{rev}.zip", files.size, bytes]
      rescue StandardError
        FileUtils.rm_rf(work) if work
        raise
      ensure
        LOCK.unlock if LOCK.owned?
      end
    end

    def svn_rev(rev)
      r = rev.to_s.strip
      return 'HEAD' if r.empty? || r.casecmp?('HEAD')
      raise Error, '리비전이 올바르지 않습니다.' unless r.match?(/\A\d{1,10}\z/)
      r
    end

    def git_rev(rev)
      r = rev.to_s.strip.presence || 'HEAD'
      raise Error, '리비전이 올바르지 않습니다.' unless r.match?(%r{\A[0-9A-Za-z][0-9A-Za-z._/\-]{0,99}\z})
      r
    end

    # 명령 실행 (셸 없이), 시간 제한 넘으면 종료. 실패 메시지에서 비밀번호는 지움
    def run(args)
      secret = args[args.index('--password') + 1] if args.include?('--password')
      output = +''
      status = nil
      Open3.popen2e({ 'LANG' => 'C.UTF-8', 'LC_ALL' => 'C.UTF-8' }, *args) do |stdin, out, wait|
        stdin.close
        reader = Thread.new { output << out.read.to_s }
        unless wait.join(TIMEOUT)
          Process.kill('TERM', wait.pid) rescue nil
          raise Error, I18n.t(:error_repo_export_timeout)
        end
        reader.join(5)
        status = wait.value
      end
      return if status&.success?
      msg = output.lines.map(&:strip).reject(&:empty?).last(2).join(' ')
      msg = msg.gsub(secret, '***') if secret.present?
      raise Error, I18n.t(:error_repo_export_failed, message: msg.truncate(200))
    end
  end
end
