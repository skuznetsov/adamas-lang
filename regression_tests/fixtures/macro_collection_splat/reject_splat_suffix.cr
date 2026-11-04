macro expand_splat
  {% tuple = {65} %}
  {{ tuple.splat(66) }}
end

expand_splat
