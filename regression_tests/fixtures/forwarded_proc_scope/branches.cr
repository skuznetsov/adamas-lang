lib ProbeC
  fun putchar(c : Int32) : Int32
end

def invoke(value : Int32, &action : Int32 -> Int32) : Int32
  action.call(value)
end

def select_path(first : Bool, second : Bool, &action : Int32 -> Int32) : Nil
  result = if first
             invoke(64, &action)
           elsif second
             value = invoke(65, &action)
             invoke(value, &action)
           else
             invoke(67, &action)
           end
  ProbeC.putchar(result)
  ProbeC.putchar(invoke(68, &action))
end

select_path(true, false) { |value| value &+ 1 }
select_path(false, true) { |value| value &+ 1 }
select_path(false, false) { |value| value &+ 1 }
