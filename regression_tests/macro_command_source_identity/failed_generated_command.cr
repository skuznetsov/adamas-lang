module GeneratedCommandFailure
  macro included
    macro fail(value)
      \{{ `exit 7` }}
    end
  end
end
class GeneratedCommandFailureUser
  include GeneratedCommandFailure
end
GeneratedCommandFailureUser.fail(0)
