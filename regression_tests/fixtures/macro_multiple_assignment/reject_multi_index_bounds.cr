macro assign_outside_array
  {%
    values = [1, 2]
    values[9], tail = [9, 8]
  %}
end

assign_outside_array
