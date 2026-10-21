lib C
  fun putchar(value : Int32) : Int32
end

macro nested_container(name, &block)
  struct {{name.id}}
    {{yield}}
  end
end

macro nested_record(name)
  struct {{name.id}}
    def self.marker : Int32
      65
    end

    def marker : Int32
      65
    end
  end
end

nested_container MacroOuter do
  nested_record MacroInner
end

def consume_macro_inner(value : MacroOuter::MacroInner) : Int32
  value.marker
end

C.putchar(MacroOuter::MacroInner.marker)
C.putchar(consume_macro_inner(MacroOuter::MacroInner.new))
