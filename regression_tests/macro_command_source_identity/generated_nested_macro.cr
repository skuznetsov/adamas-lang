lib GeneratedNestedMacroOutput
  fun putchar(value : Int32) : Int32
end

module NestedMacroBuilder
  macro included
    # The outer body deliberately has a comment before the generated macro.
    macro emit(value)
      # Emit the value \{{value}}.
      GeneratedNestedMacroOutput.putchar(\{{value}})
    end
  end
end

class NestedMacroUser
  include NestedMacroBuilder
end

NestedMacroUser.emit(65)
GeneratedNestedMacroOutput.putchar(10)
