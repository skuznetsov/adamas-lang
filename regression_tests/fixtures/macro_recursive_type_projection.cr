lib LibC
  fun exit(status : Int32) : NoReturn
end

class Array(T)
end

class Hash(K, V)
end

alias RecursiveField = Nil | Array(RecursiveField) | Hash(String, RecursiveField)
alias OtherField = RecursiveField

# The outer name must not capture the target of a namespaced alias.
alias Field = Int32
module Outer
  alias Field = Nil | Array(Field)
  alias OtherField = Field
end

{% unless Array(Outer::OtherField).name == "Array(Array(Outer::Field) | Nil)" %}
  {% raise "alias target escaped its declaration namespace" %}
{% end %}

class RecursiveProjection(T)
  def self.check
    {% for member in T.union_types %}
      {% for argument in member.type_vars %}
        {% if argument.name == "RecursiveField" %}
          {% if argument.union? || argument.class? || !argument.nilable? %}
            {% raise "recursive generic argument lost AliasType identity" %}
          {% end %}
          {% unless argument.union_types.size == 1 %}
            {% raise "recursive alias must have a singleton union_types view" %}
          {% end %}
        {% end %}
      {% end %}
    {% end %}
    41
  end
end

LibC.exit(1) unless RecursiveProjection(RecursiveField).check == 41
LibC.exit(0)
