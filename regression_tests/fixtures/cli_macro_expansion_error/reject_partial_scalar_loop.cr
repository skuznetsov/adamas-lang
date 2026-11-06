lib LibC
  fun putchar(value : Int32) : Int32
end
{% if true %}
  {% for item in 1 %}
    class ShouldNotBeGenerated
    end
  {% end %}
  class TailSurvives
    def self.marker
      65
    end
  end
{% end %}
LibC.putchar(TailSurvives.marker)
LibC.putchar(10)
