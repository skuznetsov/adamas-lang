lib LibC
  fun putchar(value : Int32) : Int32
end

struct Reader
  @available : Bool

  def initialize(@available : Bool)
  end

  def maybe : Char?
    if @available
      'A'
    else
      nil
    end
  end

  def step0
    step1
  end

  def step1
    step2
  end

  def step2
    step3
  end

  def step3
    step4
  end

  def step4
    step5
  end

  def step5
    step6
  end

  def step6
    step7
  end

  def step7
    step8
  end

  def step8
    step9
  end

  def step9
    maybe
  end

  def next_char : Char
    step0 || '\0'
  end
end

LibC.putchar(Reader.new(true).next_char.ord)
LibC.putchar(Reader.new(false).next_char.ord)
LibC.putchar(10)
