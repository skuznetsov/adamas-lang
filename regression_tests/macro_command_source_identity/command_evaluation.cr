# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Original source padding differs from both generated macro buffers.
# Direct, assigned, and generated command nodes share evaluation semantics.
lib CommandEvaluationOutput
  fun putchar(value : Int32) : Int32
  fun puts(value : UInt8*) : Int32
end
macro emit_direct(value)
  CommandEvaluationOutput.putchar({{ `printf 65` }})
end
macro emit_assigned(value)
  {% result = `printf 66` %}
  CommandEvaluationOutput.putchar({{ result }})
end
macro emit_quoted(value)
  CommandEvaluationOutput.puts({{ "printf 99" }})
end
module NestedCommandContract
  macro included
    macro emit(value)
      CommandEvaluationOutput.putchar(\{{ `printf 67` }})
    end
  end
end
class NestedCommandContractUser
  include NestedCommandContract
end
module OtherNestedCommandContract
  macro included
    macro emit(value)
      CommandEvaluationOutput.putchar(\{{ `printf 68` }})
    end
  end
end
class OtherNestedCommandContractUser
  include OtherNestedCommandContract
end
emit_direct(0)
emit_assigned(0)
OtherNestedCommandContractUser.emit(0)
NestedCommandContractUser.emit(0)
CommandEvaluationOutput.putchar(10)
emit_quoted(0)
