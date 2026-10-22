require "proc"

alias WrongInput = String -> Nil

def needs_int32_proc(callback : Proc(Int32, Nil))
end

needs_int32_proc(WrongInput.new { |value| value })
