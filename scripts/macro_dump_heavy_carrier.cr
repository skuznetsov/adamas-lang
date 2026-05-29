# Heavy carrier for ADAMAS_MACRO_BODY_OUTPUT_STATS_DUMP comparison runs.
# Many local macro expansions + default prelude (stdlib macro mix).
macro gen_methods(count)
  {% for i in 1..count %}
    def synth_{{i.id}} : Int32
      {{i}}
    end
  {% end %}
end

gen_methods(80)

macro id(x)
  {{ x }}
end

puts id(synth_40)
