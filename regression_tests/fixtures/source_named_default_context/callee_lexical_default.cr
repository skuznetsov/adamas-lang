@[Link("c")]
lib SourceDefaultLexicalC
  fun putchar(value : Int32) : Int32
end

module SourceDefaultOwner
  enum DispatchModeProbe
    Async = 65
  end

  class Emitter
    def self.accept(mode : DispatchModeProbe, *, marker : Int32) : Int32
      SourceDefaultLexicalC.putchar(69)
    end

    def self.emit(*, marker : Int32, mode : DispatchModeProbe = DispatchModeProbe::Async) : Int32
      accept(mode, marker: marker)
    end
  end
end

module CallerDefaultOwner
  enum DispatchModeProbe
    Async = 66
  end

  def self.run : Int32
    SourceDefaultOwner::Emitter.emit(marker: 1)
  end
end

CallerDefaultOwner.run
SourceDefaultLexicalC.putchar(10)
