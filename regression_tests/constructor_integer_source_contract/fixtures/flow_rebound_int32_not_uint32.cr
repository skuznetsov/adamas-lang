lib LibC
  fun putchar(value : Int32) : Int32
end

struct NumericIndex
  @slot : Int32
  @generation : UInt32

  def initialize(@slot : Int32, @generation : UInt32)
  end

  def marker : Int32
    if @slot == -1_i32 && @generation == 0_u32
      65_i32
    elsif @slot == -2147483648_i32 && @generation == 0_u32
      68_i32
    elsif @generation == 4294967295_u32
      69_i32
    else
      88_i32
    end
  end
end
generation = 0_u32
generation = 0_i32
NumericIndex.new(-1, generation)
