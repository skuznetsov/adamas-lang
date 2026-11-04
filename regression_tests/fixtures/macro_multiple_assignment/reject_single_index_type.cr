macro assign_string_index
  {%
    values = [1, 2]
    values["bad"] = 3
  %}
end

assign_string_index
