lib LibC
  fun putchar(value : Int32) : Int32
end

module ModuleParentSpace
  class Parent
    def marker : Int32
      65_i32
    end
  end
end

class ClassParentSpace
  class Parent
    def marker : Int32
      66_i32
    end
  end
end

alias ModuleParentAlias = ModuleParentSpace::Parent
alias ClassParentAlias = ClassParentSpace::Parent

class ModuleAliasChild < ModuleParentAlias
end
class ClassAliasChild < ClassParentAlias
end

LibC.putchar(ModuleAliasChild.new.marker)
LibC.putchar(ClassAliasChild.new.marker)
