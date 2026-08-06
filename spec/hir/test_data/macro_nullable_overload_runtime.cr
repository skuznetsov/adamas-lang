macro define_choose(type, result)
  def choose(value : {{type}}) : Int32
    {{result}}
  end
end

class MacroNullableOverload
  define_choose Nil, 10
  define_choose String, 20

  def run(value : String?) : Int32
    choose(value)
  end

  def probe : Int32
    run(nil) + run("x")
  end
end

macro define_nullable_choose
  def nullable_choose(value : String?) : Int32
    value ? 33 : 33
  end
end

class MacroNullableIdentity
  define_nullable_choose()

  def run(value : String?) : Int32
    nullable_choose(value)
  end

  def probe : Int32
    run(nil) + run("x")
  end
end

probe = MacroNullableOverload.new
raise "union overload dispatch mismatch" unless probe.probe == 30
raise "nil overload mismatch" unless probe.run(nil) == 10
raise "string overload mismatch" unless probe.run("x") == 20
identity = MacroNullableIdentity.new
raise "union declaration recursion" unless identity.probe == 66
raise "nil union declaration mismatch" unless identity.run(nil) == 33
raise "string union declaration mismatch" unless identity.run("x") == 33
puts "macro-nullable-overload-dispatch-ok"
