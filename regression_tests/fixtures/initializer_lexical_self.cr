lib C
  fun exit(status : Int32) : NoReturn
end

class Owner
  def self.tag : Int32
    42
  end

  def tag : Int32
    21
  end

  VALUE = self.tag

  def own_instance_tag : Int32
    self.tag
  end
end

module Namespace
  def self.tag : Int32
    27
  end

  VALUE = self.tag
end

module Nested
  class Owner
    def self.tag : Int32
      69
    end

    VALUE = self.tag
  end
end

valid = Owner::VALUE == 42 && Namespace::VALUE == 27 && Nested::Owner::VALUE == 69
C.exit(valid && Owner.new.own_instance_tag == 21 ? 0 : 1)
