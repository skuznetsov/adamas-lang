module A
  module B
    extend self

    def exec(flag, &)
      yield
    end
  end
end
