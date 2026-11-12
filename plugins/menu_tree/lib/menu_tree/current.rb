# 요청마다 비워지는 캐시 (사이트 이름 등)
module MenuTree
  class Current < ActiveSupport::CurrentAttributes
    attribute :sites
  end
end
