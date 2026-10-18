macro invoke_delayed_before_definition
  delayed_value(59)
end

invoke_delayed_before_definition

macro define_delayed
  macro delayed_value(input)
    {% verbatim do %}
      {{ input }}
    {% end %}
  end
end

define_delayed
