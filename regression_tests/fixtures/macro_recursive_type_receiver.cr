lib C
  fun exit(status : Int32) : NoReturn
end
# Explicit declarations make this a standalone no-prelude type-graph probe.
class Array(T)
end
class Hash(K, V)
end
alias RecursiveField = Nil | Array(RecursiveField) | Hash(String, RecursiveField)
alias RecursiveArray = Array(RecursiveField)
{% raise "recursive alias must be a union" unless RecursiveField.union? %}
{% raise "recursive array receiver must be a class" unless RecursiveArray.class? %}
{% raise "recursive array must have one type argument" unless RecursiveArray.type_vars.size == 1 %}
C.exit(0)
