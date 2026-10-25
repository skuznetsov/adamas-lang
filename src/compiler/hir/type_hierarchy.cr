module Adamas::HIR
  # Single owner of the nominal type graph used during lowering: class parent
  # edges and module include edges, plus the derived queries every caller
  # needs (subclasses, includer key lookup, transitive includers, virtual
  # dispatch targets). Writers go through `add_parent_edge`/`add_inclusion`,
  # so the derived caches are invalidated in one place.
  #
  # Include edges are stored as recorded: a class including M2 (which
  # includes M1) is registered under both M2 and M1, while a module including
  # a module is one edge from the inner module to the outer one. Queries that
  # need every reachable owner therefore walk module includers transitively.
  class TypeHierarchy
    # Result of resolving a module spelling to its includer set. `module_base`
    # is the key that matched through the suffix index; a short-name hit keeps
    # the spelling that was asked for.
    record IncluderLookup, module_base : String, includers : Set(String)?

    # Children keyed by every spelling of the parent (exact, generic base,
    # short name, short base).
    getter children_by_parent : Hash(String, Set(String))
    getter module_includers : Hash(String, Set(String))

    def initialize(
      @class_info : Hash(String, ClassInfo),
      @module_defs : Hash(String, Array({Adamas::Compiler::Frontend::ModuleNode, Adamas::Compiler::Frontend::ArenaLike})),
    )
      @children_by_parent = {} of String => Set(String)
      @subclasses_cache = {} of String => Array(String)
      @module_includers = {} of String => Set(String)
      @includer_keys_by_suffix = {} of String => Set(String)
    end

    # Records `child < parent` under every parent spelling. Returns the
    # parent keys when a new edge was added, nil otherwise.
    def add_parent_edge(child_name : String, parent_name : String) : Set(String)?
      parent_base = TypeHierarchy.strip_generic_args(parent_name)
      keys = Set(String).new
      keys << parent_name
      keys << parent_base if parent_base != parent_name
      short = TypeHierarchy.last_namespace_component(parent_name)
      keys << short if short != parent_name
      short_base = TypeHierarchy.last_namespace_component(parent_base)
      keys << short_base if short_base != parent_base
      edge_added = false
      keys.each do |key|
        children = (@children_by_parent[key] ||= Set(String).new)
        unless children.includes?(child_name)
          children << child_name
          edge_added = true
        end
      end
      return nil unless edge_added

      # A new edge changes the descendant set for the parent and every cached
      # ancestor that already contained one of the parent's aliases. Keep the
      # invalidation bounded to those roots instead of dropping the whole cache.
      stale_roots = [] of String
      @subclasses_cache.each do |root, descendants|
        next unless keys.includes?(root) || descendants.any? { |name| keys.includes?(name) }
        stale_roots << root
      end
      stale_roots.each { |root| @subclasses_cache.delete(root) }
      keys
    end

    def clear_subclass_cache : Nil
      @subclasses_cache.clear
    end

    # Records that `includer` (a class or a module) includes `module_key`.
    # Returns true when the edge is new.
    def add_inclusion(module_key : String, includer : String) : Bool
      set = @module_includers[module_key]?
      unless set
        set = Set(String).new
        @module_includers[module_key] = set
        # The suffix index is keyed only by module name, so populate it once
        # per module.
        module_base = TypeHierarchy.strip_generic_args(module_key)
        suffix_start = 0
        loop do
          suffix = module_base[suffix_start..]
          break unless suffix
          (@includer_keys_by_suffix[suffix] ||= Set(String).new) << module_key

          next_sep = module_base.index("::", suffix_start)
          break unless next_sep
          suffix_start = next_sep + 2
        end
      end
      return false if set.includes?(includer)
      set.add(includer)
      true
    end

    def direct_children(parent : String) : Set(String)?
      @children_by_parent[parent]?
    end

    # Transitive subclasses of `parents` (classes only, parents excluded), in
    # breadth-first order.
    def subclasses_of(parents : Array(String)) : Array(String)
      results = [] of String
      visited = Set(String).new
      queue = Array(String).new(parents.size)
      parents.each { |p| queue << p }
      queue.each { |parent| visited.add(parent) }
      idx = 0
      while idx < queue.size
        parent = queue[idx]
        idx += 1
        if children = @children_by_parent[parent]?
          children.each do |child|
            next if visited.includes?(child)
            visited.add(child)
            results << child
            queue << child
          end
        end
      end
      results
    end

    def subclasses(parent : String) : Array(String)
      @subclasses_cache[parent] ||= subclasses_of([parent])
    end

    # A registered module definition with no class/struct of the same name.
    def module?(name : String) : Bool
      !@class_info.has_key?(name) && @module_defs.has_key?(TypeHierarchy.strip_generic_args(name))
    end

    # True when `name` (or its short form) is an includer key, either exactly
    # or as a namespace suffix of one.
    def includer_key?(name : String) : Bool
      @module_includers.has_key?(name) || @includer_keys_by_suffix.has_key?(name)
    end

    # Resolves a module spelling (without generic arguments) to its includer
    # set: exact key, then a unique key with that namespace suffix, then the
    # short name, then a unique key with the short-name suffix.
    def includer_lookup(module_base : String) : IncluderLookup
      includers = @module_includers[module_base]?
      if includers.nil? || includers.empty?
        if matches = @includer_keys_by_suffix[module_base]?
          if matches.size == 1
            module_base = matches.first
            includers = @module_includers[module_base]?
          end
        end
      end
      if includers.nil? || includers.empty?
        short_name = TypeHierarchy.last_namespace_component(module_base)
        if short_name != module_base
          includers = @module_includers[short_name]?
          if includers.nil? || includers.empty?
            if matches = @includer_keys_by_suffix[short_name]?
              if matches.size == 1
                module_base = matches.first
                includers = @module_includers[module_base]?
              end
            end
          end
        end
      end
      IncluderLookup.new(module_base, includers)
    end

    # Yields every type that includes `owner` (exact spelling and generic
    # base), following modules that include modules. Each includer is yielded
    # once, in breadth-first order, with whether it is a module.
    def each_transitive_includer(owner : String, & : String, Bool ->) : Nil
      queue = [owner]
      base = TypeHierarchy.strip_generic_args(owner)
      queue << base unless base == owner
      visited = Set(String).new
      yielded = Set(String).new
      while module_name = queue.shift?
        next unless visited.add?(module_name)
        includers = @module_includers[module_name]? || next
        includers.each do |includer|
          next if visited.includes?(includer)
          next unless yielded.add?(includer)
          if module?(includer)
            yield includer, true
            queue << includer
          else
            yield includer, false
          end
        end
      end
    end

    # Concrete types a virtual call on `owner` can dispatch to: subclasses of
    # a class, and for a module its (transitive) includers and their
    # subclasses.
    def dispatch_targets(owner : String) : Array(String)
      results = subclasses(owner).dup
      seen = results.to_set
      each_transitive_includer(owner) do |includer, is_module|
        next if is_module
        results << includer if seen.add?(includer)
        subclasses(includer).each do |name|
          results << name if seen.add?(name)
        end
      end
      results
    end

    @[AlwaysInline]
    def self.strip_generic_args(name : String) : String
      i = 0
      while i < name.bytesize
        if name.to_unsafe[i] == '('.ord
          return name.byte_slice(0, i)
        end
        i += 1
      end
      name
    end

    def self.last_namespace_component(name : String) : String
      i = name.bytesize - 2
      while i >= 0
        if name.to_unsafe[i] == ':'.ord && name.to_unsafe[i + 1] == ':'.ord
          start = i + 2
          return "" if start >= name.bytesize
          return name.byte_slice(start, name.bytesize - start)
        end
        i -= 1
      end
      name
    end
  end
end
