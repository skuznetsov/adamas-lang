struct GenericStructParent(T)
end
class GenericClassChild < GenericStructParent(Int32)
end
