lib LibC
  fun exit(status : Int32) : NoReturn
end

module Domain
  class Proc
    def call(value : Int32)
      value
    end
  end

  def self.apply(value, transform : Proc)
    transform.call(value)
  end
end

LibC.exit(1) unless Domain.apply(7, Domain::Proc.new) == 7
LibC.exit(0)
