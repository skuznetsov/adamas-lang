#                                          x : String= 0                                                                                                                        #
lib LibC
  fun putchar(value : Int32) : Int32
end

class GeneratedParameterSource
  {% begin %}
    def self.value(argument = nil)
      65
    end
  {% end %}
  def self.value(argument : Bool)
    66
  end
end
LibC.putchar(GeneratedParameterSource.value(nil))
