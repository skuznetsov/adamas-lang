module M
  {% if flag?(:tracing) %}
    def self.foo : Int32
      1
    end
  {% else %}
    def self.foo : Int32
      2
    end
  {% end %}
end

M.foo
