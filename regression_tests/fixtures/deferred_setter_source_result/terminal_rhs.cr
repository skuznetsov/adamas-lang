lib LibC
  fun exit(status : Int32) : NoReturn
end
class Box
  def value=(value : Int32)
    65
  end
end
def stop : NoReturn
  LibC.exit(0)
end
Box.new.value = stop
