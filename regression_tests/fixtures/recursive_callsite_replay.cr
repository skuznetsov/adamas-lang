lib C
  fun putchar(c : Int32) : Int32
end

struct Ticket
  def initialize(@value : Int32)
  end

  def value : Int32
    @value
  end
end

module Mini
  # Five forwarding calls reach the normal result-inference depth boundary.
  class Parser
    STOP_0 = Ticket.new(65)
    STOP_1 = Ticket.new(66)
    STOP_2 = Ticket.new(67)
    STOP_3 = Ticket.new(68)

    def initialize(@remaining : Int32, @left : Bool)
    end

    def entry0 : Ticket
      entry1
    end

    def entry1 : Ticket
      entry2
    end

    def entry2 : Ticket
      entry3
    end

    def entry3 : Ticket
      entry4
    end

    def entry4 : Ticket
      read0
    end

    def read0 : Ticket
      return STOP_0 if @remaining == 0
      @remaining = @remaining &- 1
      if @left
        current = read1
        return current
      end
      read3
    end

    def read1 : Ticket
      return STOP_1 if @remaining == 0
      @remaining = @remaining &- 1
      if @left
        current = read2
        return current
      end
      read3
    end

    def read2 : Ticket
      return STOP_2 if @remaining == 0
      @remaining = @remaining &- 1
      if @left
        current = read3
        return current
      end
      read0
    end

    def read3 : Ticket
      return STOP_3 if @remaining == 0
      @remaining = @remaining &- 1
      if @left
        current = read0
        return current
      end
      read2
    end
  end
end

C.putchar(Mini::Parser.new(6, true).entry0.value)
C.putchar(Mini::Parser.new(4, false).entry0.value)
C.putchar(10)
