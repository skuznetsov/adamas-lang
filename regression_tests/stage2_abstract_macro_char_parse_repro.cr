abstract struct Foo
  def self.test(string)
    {% begin %}
      string.each_char do |char|
        next if char == 'x'
      end
    {% end %}
  end
end
