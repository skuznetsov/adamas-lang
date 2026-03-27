module PointerLinkedList
  module Node
    macro included
      property previous : ::Pointer(self) = ::Pointer(self).null
      property next : ::Pointer(self) = ::Pointer(self).null
    end
  end
end

module Crystal
  module Once
    struct Operation
      include PointerLinkedList::Node
    end
  end
end
