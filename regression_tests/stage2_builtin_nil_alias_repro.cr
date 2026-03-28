module Crystal
  module PointerLinkedList
    module Node
      class Nil
      end
    end
  end

  class Once
    class Operation
      include PointerLinkedList::Node

      def resume_all : Nil
      end
    end
  end
end
