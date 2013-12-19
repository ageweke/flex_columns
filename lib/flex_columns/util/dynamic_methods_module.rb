module FlexColumns
  module Util
    # A DynamicMethodsModule is used to add dynamically-generated methods to an existing class.
    #
    # Why do we need a module to do that? Why can't we simply call #define_method on the class itself?
    #
    # We could. However, if you do that, a few problems crop up:
    #
    # * There is no precendence that you can control. If you define a method +:foo+ on class Bar, then that method is
    #   always run when an instance of that class is sent the message +:foo+. The only way to change the behavior of
    #   that class is to completely redefine that method, which brings us to the second problem...
    # * Overriding and +super+ doesn't work. That is, you can't override such a method and call the original method
    #   using +super+. You're reduced to using +alias_method_chain+, which is a mess.
    # * There's no namespacing at all -- at runtime, it's not even remotely clear where these methods are coming from.
    # * Finally, if you're living in a dynamic environment -- like Rails' development mode, where classes get reloaded
    #   very frequently -- once you define a method, it is likely to be forever defined. You have to write code to keep
    #   track of what you've defined, and remove it when it's no longer present.
    #
    # A DynamicMethodsModule fixes these problems. It's little more than a Module that lets you define methods (and
    # helpfully makes #define_method +public+ to help), but it also will include itself into a target class and bind
    # itself to a constant in that class (which magically gives the module a name, too). Further, it also keeps track
    # of which methods you've defined, and can remove them all with #remove_all_methods!. This allows you to construct
    # a much more reliable paradigm: instead of trying to figure out what methods you should remove and add when things
    # change, you can just call #remove_all_methods! and then redefine whatever methods _currently_ should exist.
    class DynamicMethodsModule < ::Module
      # Creates a new instance. +target_class+ is the Class into which this module should include itself; +name+ is the
      # name to which it should bind itself. (This will be bound as a constant inside that class, not at top-level on
      # Object; so, for example, if +target_class+ is +User+ and +name+ is +Foo+, then this module will end up named
      # +User::Foo+, not simply +Foo+.)
      #
      # If passed a block, the block will be evaluated in the context of this module, just like Module#new. Note that
      # you <em>should not</em> use this to define methods that you want #remove_all_methods!, below, to remove; it
      # won't work. Any methods you add in this block using normal +def+ will persist, even through #remove_all_methods!.
      def initialize(target_class, name, &block)
        raise ArgumentError, "Target class must be a Class, not: #{target_class.inspect}" unless target_class.kind_of?(Class)
        raise ArgumentError, "Name must be a Symbol or String, not: #{name.inspect}" unless name.kind_of?(Symbol) || name.kind_of?(String)

        @target_class = target_class
        @name = name.to_sym

        # Unfortunately, there appears to be no way to "un-include" a Module in Ruby -- so we have no way of replacing
        # an existing DynamicMethodsModule on the target class, which is what we'd really like to do in this situation.
        if @target_class.const_defined?(@name)
          existing = @target_class.const_get(@name)

          if existing && existing != self
            raise NameError, %{You tried to define a #{self.class.name} named #{name.inspect} on class #{target_class.name},
but that class already has a constant named #{name.inspect}: #{existing.inspect}}
          end
        end

        @target_class.const_set(@name, self)
        @target_class.send(:include, self)

        @methods_defined = { }

        super(&block)
      end

      # Removes all methods that have been defined on this module using #define_method, below. (If you use some other
      # mechanism to define a method on this DynamicMethodsModule, then it will not be removed when this method is
      # called.)
      def remove_all_methods!
        instance_methods.each do |method_name|
          # Important -- we use Class#remove_method, not Class#undef_method, which does something that's different in
          # some important ways.
          remove_method(method_name) if @methods_defined[method_name.to_sym]
        end
      end

      # Defines a method. Works identically to Module#define_method, except that it's +public+ and #remove_all_methods!
      # will remove the method.
      def define_method(name, &block)
        name = name.to_sym
        super(name, &block)
        @methods_defined[name] = true
      end

      # Makes it so you can say, for example:
      #
      #     my_dynamic_methods_module.define_method(:foo) { ... }
      #     my_dynamic_methods_module.private(:foo)
      public :private # teehee
    end
  end
end
