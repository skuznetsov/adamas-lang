macro fail_command(value)
  {{ `exit #{value}` }}
end
fail_command(7)
