def accept_lexical_marker(value : Int32) : Int32
  value
end
class LexicalReceiverBase
  MARKER = 65
  def self.make : self
    accept_lexical_marker(MARKER)
    self.new
  end
end
class LexicalReceiverChild < LexicalReceiverBase
  MARKER = "wrong lexical owner"
end
value : LexicalReceiverChild = LexicalReceiverChild.make
