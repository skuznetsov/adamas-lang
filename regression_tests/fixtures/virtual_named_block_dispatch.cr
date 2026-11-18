require "primitives"
lib LibC
  fun putchar(code : Int32) : Int32
end

module Work
  abstract def visit(*, name : String?, enabled : Bool, &block : ->) : Int32
  abstract def visit(*, title : String?, enabled : Bool, &block : ->) : Int32
end

class Left
  include Work

  def visit(*, name : String?, enabled : Bool, &block : ->) : Int32
    block.call
    return 90 unless enabled
    name ? 65 : 66
  end

  def visit(*, title : String?, enabled : Bool, &block : ->) : Int32
    block.call
    return 90 unless enabled
    title ? 69 : 70
  end
end

class Right
  include Work

  def visit(*, name : String?, enabled : Bool, &block : ->) : Int32
    block.call
    return 90 unless enabled
    name ? 67 : 68
  end

  def visit(*, title : String?, enabled : Bool, &block : ->) : Int32
    block.call
    return 90 unless enabled
    title ? 71 : 72
  end
end

def source(left : Bool) : Work
  left ? Left.new : Right.new
end

def via_name(left : Bool, *, name : String? = nil, enabled = false, &block)
  source(left).visit(name: name, enabled: enabled, &block)
end

def via_title(left : Bool, *, title : String? = nil, enabled = false, &block)
  source(left).visit(title: title, enabled: enabled, &block)
end

LibC.putchar(via_name(true, name: "s", enabled: true) { LibC.putchar(46) })
LibC.putchar(via_name(true, name: nil, enabled: true) { LibC.putchar(46) })
LibC.putchar(via_name(false, name: "s", enabled: true) { LibC.putchar(46) })
LibC.putchar(via_name(false, name: nil, enabled: true) { LibC.putchar(46) })
LibC.putchar(via_title(true, title: "s", enabled: true) { LibC.putchar(46) })
LibC.putchar(via_title(true, title: nil, enabled: true) { LibC.putchar(46) })
LibC.putchar(via_title(false, title: "s", enabled: true) { LibC.putchar(46) })
LibC.putchar(via_title(false, title: nil, enabled: true) { LibC.putchar(46) })
LibC.putchar(10)
