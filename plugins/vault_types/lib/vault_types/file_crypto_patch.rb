# 접속정보 키 파일 암호화 보정 (Vault 0.10.5 원본은 고치지 않고 덮어씀)
# - 원본 문제: 저장(after_save)·전체 암호화 때마다 이미 암호화된 파일을 또 암호화 → 이중 암호화로 키를 못 읽음
#              [다운로드]는 디스크의 암호문을 그대로 보냄, 읽기는 한 겹만 풂
# - 보정: 암호화는 한 번만(이미 암호화면 건너뜀) · 읽기/해제는 여러 겹이어도 끝까지 풂 · 다운로드는 푼 내용
module VaultTypes
  module FileCryptoPatch
  module FileCrypto
    MAX_LAYERS = 5

    module_function

    # 현재 엔진 기준으로 이 내용이 암호문인지
    def encrypted?(content)
      return false if content.nil? || content.empty?
      engine = Encryptor.engine
      return false if engine == NullCipher
      if engine == RedmineCipher
        content.start_with?('aes-256-cbc:')
      else
        # VaultCipher(AES-128-ECB + Base64): 형식이 맞고 실제로 풀려야 암호문
        return false unless content.match?(/\A[A-Za-z0-9+\/=\r\n]+\z/)
        engine.decrypt_text(content)
        true
      end
    rescue StandardError
      false
    end

    # 여러 겹이어도 끝까지 풂 → [원문, 풀어낸 겹 수]
    def peel(content)
      layers = 0
      while layers < MAX_LAYERS && encrypted?(content)
        plain = Encryptor.decrypt(content)
        break if plain.nil? || plain == content
        content = plain
        layers += 1
      end
      [content, layers]
    end
  end

  module KeyModel
    def encrypt_file!
      return false unless file.present?
      path = File.join(Vault::KEYFILES_DIR, file)
      return false unless File.exist?(path)
      raw = File.binread(path)
      return true if VaultTypes::FileCryptoPatch::FileCrypto.encrypted?(raw) # 이미 암호화 — 다시 하지 않음
      File.binwrite(path, Encryptor.encrypt(raw))
      true
    rescue StandardError => e
      Rails.logger.error("File encryption failed for key #{id}: #{e.message}")
      false
    end

    def decrypt_file!
      return false unless file.present?
      path = File.join(Vault::KEYFILES_DIR, file)
      return false unless File.exist?(path)
      plain, = VaultTypes::FileCryptoPatch::FileCrypto.peel(File.binread(path))
      File.binwrite(path, plain)
      true
    rescue StandardError => e
      Rails.logger.error("File decryption failed for key #{id}: #{e.message}")
      false
    end

    def file_content
      return nil unless file.present?
      path = File.join(Vault::KEYFILES_DIR, file)
      return nil unless File.exist?(path)
      VaultTypes::FileCryptoPatch::FileCrypto.peel(File.binread(path)).first
    rescue StandardError => e
      Rails.logger.error("Failed to read file content for key #{id}: #{e.message}")
      nil
    end
  end

  module Download
    # 디스크의 암호문 대신 푼 내용을 내려 줌
    def download
      find_key
      return if @key.nil?
      data = @key.file_content
      return render_404 if data.nil?
      send_data data, filename: @key.name, type: 'application/octet-stream'
    end
  end
end
end
