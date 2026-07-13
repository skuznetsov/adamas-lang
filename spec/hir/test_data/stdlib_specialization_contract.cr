module Outer
  module Inner
    struct Point
      def initialize(@x : Int32, @y : Int32)
      end

      def to_s(io : IO) : Nil
        io << @x << ',' << @y
      end
    end
  end
end

value = 1.25_f64
puts sprintf("%.3f", value)
puts [Outer::Inner::Point.new(1, 2)].inspect
