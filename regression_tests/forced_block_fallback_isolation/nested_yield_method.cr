lib LibC
  fun exit(status : Int32) : NoReturn
end

module CS
  def self.dladdr(ip, &)
    if ip > 2
      yield ip &- 1, ip &+ 1, 2
    end
  end

  def self.decode_frame(ip)
    decode_frame(ip) do |offset, symbol, file|
      {offset, symbol, file}
    end
  end

  private def self.decode_frame(ip, &)
    original_ip = ip
    while true
      retry = dladdr(ip) do |file, symbol, address|
        offset = original_ip &- address
        if offset == 0
          ip = ip &- 1
          true
        elsif symbol == 0 && file == 0
          false
        else
          return yield offset, symbol, file
        end
      end
      break unless retry
    end
  end

  def self.dbf(ip, flag)
    if frame = decode_frame(ip)
      a, b, c = frame
      a &+ b &+ c
    else
      77
    end
  end
end

def twice(&)
  a = yield 5
  b = yield 1
  (a || 0) &+ (b || 0)
end

def drive
  twice { |ip| CS.dbf(ip, true) }
end

LibC.exit(drive)
