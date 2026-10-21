lib LibC
  fun putchar(value : Int32) : Int32
end

class AliasBehaviorParent
  def marker : Int32
    65_i32
  end
end

alias AliasBehaviorParentName = AliasBehaviorParent

class AliasBehaviorChild < AliasBehaviorParentName
end

LibC.putchar(AliasBehaviorChild.new.marker)
