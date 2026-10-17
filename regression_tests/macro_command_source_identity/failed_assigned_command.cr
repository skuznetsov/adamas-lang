macro fail_command(value)
  {% result = `exit 7` %}
  {{ result }}
end
fail_command(0)
