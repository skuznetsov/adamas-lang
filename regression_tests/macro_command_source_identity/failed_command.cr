macro fail_command(value)
  {{ `exit 7` }}
end
fail_command(0)
