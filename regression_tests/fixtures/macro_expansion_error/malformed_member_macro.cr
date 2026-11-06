macro malformed_member
  {{ "def generated())".id }}
end

class MacroMemberErrorProbe
  malformed_member
end

MacroMemberErrorProbe.new
