# 파일 창 작업 (net-sftp) — 목록 · 받기 · 올리기 · 폴더 만들기 · 이름 바꾸기 · 삭제
# 경로는 서버 쪽 경로 그대로 (터미널에서 할 수 있는 일과 같은 범위 — 그 계정 권한으로)
module SshConsole
  module Files
    module_function

    MAX_LIST = 3000
    MAX_UPLOAD = 500 * 1024 * 1024
    CHUNK = 64 * 1024

    def join(dir, name)
      name = name.to_s
      raise TargetError, I18n.t(:error_ssh_files_name) if name.empty? || name.include?('/') || %w(. ..).include?(name) || name.include?("\0")
      dir.to_s.end_with?('/') ? "#{dir}#{name}" : "#{dir}/#{name}"
    end

    def parent(path)
      p = File.dirname(path.to_s)
      p.empty? ? '/' : p
    end

    def perms(mode)
      return '' unless mode
      t = { 0o040000 => 'd', 0o120000 => 'l' }[mode & 0o170000] || '-'
      t + [6, 3, 0].map { |sh| m = (mode >> sh) & 7; (m & 4 > 0 ? 'r' : '-') + (m & 2 > 0 ? 'w' : '-') + (m & 1 > 0 ? 'x' : '-') }.join
    end

    # → { path:, parent:, entries: [{ name, dir, link, size, mtime, perms }], more: }
    def list(sftp, path)
      path = path.to_s.strip
      path = '.' if path.empty?
      real = sftp.realpath!(path).name
      items = []
      sftp.dir.foreach(real) do |e|
        next if %w(. ..).include?(e.name)
        a = e.attributes
        dir = a.directory?
        if a.symlink?
          dir = (sftp.stat!(join(real, e.name)).directory? rescue false)
        end
        items << { name: e.name.dup.force_encoding('UTF-8').scrub, dir: dir, link: a.symlink?, size: a.size, mtime: a.mtime, perms: perms(a.permissions) }
        break if items.size > MAX_LIST
      end
      more = items.size > MAX_LIST
      items = items.first(MAX_LIST).sort_by { |x| [x[:dir] ? 0 : 1, x[:name].downcase] }
      { path: real, parent: (real == '/' ? nil : parent(real)), entries: items, more: more }
    end

    def stat(sftp, path)
      sftp.stat!(path)
    end

    # 파일 끝을 지나 읽으면 net-sftp 가 응답을 기다리며 멈춤(4.1.1) → 처음 크기만큼만 정확히 읽음
    # (받는 동안 커지는 로그는 받기 시작한 시점까지)
    def download(sftp, path, size)
      left = size.to_i
      sftp.file.open(path, 'r') do |f|
        while left.positive?
          data = f.read([CHUNK, left].min)
          break if data.nil? || data.empty?
          left -= data.bytesize
          yield data
        end
      end
    end

    def upload(sftp, dir, name, io)
      dest = join(dir, name)
      size = 0
      sftp.file.open(dest, 'w') do |f|
        while (data = io.read(CHUNK))
          f.write(data)
          size += data.bytesize
        end
      end
      [dest, size]
    end

    def mkdir(sftp, dir, name)
      dest = join(dir, name)
      sftp.mkdir!(dest)
      dest
    end

    def rename(sftp, path, name)
      dest = join(parent(path), name)
      sftp.rename!(path, dest)
      dest
    end

    # 파일은 지우고, 폴더는 비어 있을 때만 (실수로 통째로 지우지 않게)
    def delete(sftp, path)
      if sftp.stat!(path).directory?
        sftp.rmdir!(path)
      else
        sftp.remove!(path)
      end
    end
  end
end
