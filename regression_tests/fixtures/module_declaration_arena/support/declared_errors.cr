module ArenaRepro
  nil

  class TopError < Exception
  end
end

module ArenaRepro::Nested
  raise "unreachable" unless true

  class NestedError < Exception
  end

  class Unrelated
  end
end
