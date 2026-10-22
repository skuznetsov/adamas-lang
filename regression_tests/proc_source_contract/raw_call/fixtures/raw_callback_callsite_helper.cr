class RawCallbackCallsiteSource
  def self.emit(seed, use_seed, &block)
    if use_seed
      yield seed
    else
      yield 66_i32
    end
  end
end
