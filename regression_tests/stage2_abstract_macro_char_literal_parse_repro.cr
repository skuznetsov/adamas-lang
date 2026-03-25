abstract struct Foo
  def self.test
    {% begin %}
      'x'
    {% end %}
  end
end
