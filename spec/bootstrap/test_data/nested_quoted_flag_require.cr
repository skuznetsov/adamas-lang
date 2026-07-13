lib LibC
  fun printf(format : UInt8*, ...) : Int32
end

{% if flag?(:unix) %}
  {% if flag?("unix") %}
    require "./nested_quoted_flag_child"
  {% else %}
    require "./nested_quoted_flag_fallback"
  {% end %}
{% end %}

LibC.printf("ADAMAS_NESTED_QUOTED_FLAG_VALUE:%d\n", NestedQuotedFlagProbe::VALUE)
