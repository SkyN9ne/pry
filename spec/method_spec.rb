# frozen_string_literal: true

require 'set'

describe Pry::Method do
  it "should use String names for compatibility" do
    klass = Class.new { def hello; end }
    expect(Pry::Method.new(klass.instance_method(:hello)).name).to eq "hello"
  end

  describe ".from_str" do
    it 'looks up instance methods if no methods available and no options provided' do
      klass = Class.new { def hello; end }
      meth = Pry::Method.from_str(:hello, Pry.binding_for(klass))
      expect(meth).to eq klass.instance_method(:hello)
    end

    it 'looks up methods if no instance methods available and no options provided' do
      klass = Class.new { def self.hello; end }
      meth = Pry::Method.from_str(:hello, Pry.binding_for(klass))
      expect(meth).to eq klass.method(:hello)
    end

    it(
      'looks up instance methods first even if methods available and no ' \
      'options provided'
    ) do
      klass = Class.new do
        def hello; end

        def self.hello; end
      end
      meth = Pry::Method.from_str(:hello, Pry.binding_for(klass))
      expect(meth).to eq klass.instance_method(:hello)
    end

    it 'should look up instance methods if "instance-methods"  option provided' do
      klass = Class.new do
        def hello; end

        def self.hello; end
      end
      meth = Pry::Method.from_str(
        :hello, Pry.binding_for(klass), "instance-methods" => true
      )
      expect(meth).to eq klass.instance_method(:hello)
    end

    it 'should look up methods if :methods  option provided' do
      klass = Class.new do
        def hello; end

        def self.hello; end
      end
      meth = Pry::Method.from_str(:hello, Pry.binding_for(klass), methods: true)
      expect(meth).to eq klass.method(:hello)
    end

    it 'should look up instance methods using the Class#method syntax' do
      klass = Class.new do
        def hello; end

        def self.hello; end
      end
      meth = Pry::Method.from_str("klass#hello", Pry.binding_for(binding))
      expect(meth).to eq klass.instance_method(:hello)
    end

    it 'should look up methods using the object.method syntax' do
      klass = Class.new do
        def hello; end

        def self.hello; end
      end
      meth = Pry::Method.from_str("klass.hello", Pry.binding_for(binding))
      expect(meth).to eq klass.method(:hello)
    end

    it(
      'should NOT look up instance methods using the Class#method syntax if ' \
      'no instance methods defined'
    ) do
      _klass = Class.new { def self.hello; end }
      meth = Pry::Method.from_str("_klass#hello", Pry.binding_for(binding))
      expect(meth).to eq nil
    end

    it(
      'should NOT look up methods using the object.method syntax if no ' \
      'methods defined'
    ) do
      _klass = Class.new { def hello; end }
      meth = Pry::Method.from_str("_klass.hello", Pry.binding_for(binding))
      expect(meth).to eq nil
    end

    it 'should look up methods using klass.new.method syntax' do
      _klass = Class.new { def hello; :hello; end }
      meth = Pry::Method.from_str("_klass.new.hello", Pry.binding_for(binding))
      expect(meth.name).to eq "hello"
    end

    it 'should take care of corner cases like mongo[] e.g Foo::Bar.new[]- issue 998' do
      _klass = Class.new { def []; :hello; end }
      meth = Pry::Method.from_str("_klass.new[]", Pry.binding_for(binding))
      expect(meth.name).to eq "[]"
    end

    it 'should take care of cases like $ mongo[] - issue 998' do
      f = Class.new { def []; :hello; end }.new
      meth = Pry::Method.from_str("f[]", Pry.binding_for(binding))
      expect(meth).to eq f.method(:[])
    end

    it 'should look up instance methods using klass.meth#method syntax' do
      _klass = Class.new { def self.meth; Class.new; end }
      meth = Pry::Method.from_str("_klass.meth#initialize", Pry.binding_for(binding))
      expect(meth.name).to eq "initialize"
    end

    it 'should look up methods using instance::bar syntax' do
      _klass = Class.new { def self.meth; Class.new; end }
      meth = Pry::Method.from_str("_klass::meth", Pry.binding_for(binding))
      expect(meth.name).to eq "meth"
    end

    it 'should not raise an exception if receiver does not exist' do
      expect { Pry::Method.from_str("random_klass.meth", Pry.binding_for(binding)) }
        .to_not raise_error
    end
  end

  describe '.from_binding' do
    it 'should be able to pick a method out of a binding' do
      klass = Class.new { def self.foo; binding; end }.foo
      expect(Pry::Method.from_binding(klass).name).to eq('foo')
    end

    it 'should NOT find a method from the toplevel binding' do
      expect(Pry::Method.from_binding(TOPLEVEL_BINDING)).to eq nil
    end

    it "should find methods that have been undef'd" do
      c = Class.new do
        def self.bar
          class << self; undef bar; end
          binding
        end
      end

      m = Pry::Method.from_binding(c.bar)
      expect(m.name).to eq "bar"
    end

    it 'should find the super method correctly' do
      # rubocop:disable Layout/EmptyLineBetweenDefs
      a = Class.new { def gag33; binding; end; def self.line; __LINE__; end }
      # rubocop:enable Layout/EmptyLineBetweenDefs

      b = Class.new(a) { def gag33; super; end }

      g = b.new.gag33
      m = Pry::Method.from_binding(g)

      expect(m.owner).to eq a
      expect(m.source_line).to eq a.line
      expect(m.name).to eq "gag33"
    end

    it 'should find the right method if a super method exists' do
      a = Class.new { def gag; binding; end; }

      # rubocop:disable Layout/EmptyLineBetweenDefs
      b = Class.new(a) { def gag; super; binding; end; def self.line; __LINE__; end }
      # rubocop:enable Layout/EmptyLineBetweenDefs

      m = Pry::Method.from_binding(b.new.gag)

      expect(m.owner).to eq b
      expect(m.source_line).to eq b.line
      expect(m.name).to eq "gag"
    end

    it "should find the right method from a BasicObject" do
      # rubocop:disable Layout/EmptyLineBetweenDefs
      a = Class.new(BasicObject) do
        def gag; ::Kernel.binding; end; def self.line; __LINE__; end
      end
      # rubocop:enable Layout/EmptyLineBetweenDefs

      m = Pry::Method.from_binding(a.new.gag)
      expect(m.owner).to eq a
      expect(m.source_file).to eq __FILE__
      expect(m.source_line).to eq a.line
    end

    it 'should find the right method even if it was renamed and replaced' do
      o = Object.new
      class << o
        def borscht
          @nips = "nips"
          binding
        end
        alias_method :paella, :borscht
        def borscht() paella end
      end

      m = Pry::Method.from_binding(o.borscht)
      expect(m.source).to eq Pry::Method(o.method(:paella)).source
    end

    it 'should not find a wrong method by matching on nil source location' do
      included_module = Module.new do
        def self.included(base)
          base.send :alias_method, "respond_to_without_variables?", "respond_to?"
          base.send :alias_method, "respond_to?", "respond_to_with_variables?"
        end

        def respond_to_with_variables?(sym, include_priv = false)
          respond_to_without_variables?(sym, include_priv)
        end
      end

      o = Object.new
      class << o
        attr_reader :tasks
        def task(name, &block)
          @tasks ||= {}
          @tasks[name] = block
        end

        def load_task
          path = File.expand_path("spec/fixtures/test_task.rb")
          instance_eval File.read(path), path
        end
      end

      o.load_task

      o2 = Object.new
      o2.singleton_class.send(:include, included_module)

      # Verify preconditions.
      expect(o2.method(:respond_to_without_variables?).source_location).to be_nil

      b = o2.instance_eval(&o.tasks[:test_task])
      expect(Pry::Method.from_binding(b).name).to eq "load_task"
    end
  end

  describe 'super' do
    it 'should be able to find the super method on a bound method' do
      a = Class.new { def rar; 4; end }
      b = Class.new(a) { def rar; super; end }

      obj = b.new

      zuper = Pry::Method(obj.method(:rar)).super
      expect(zuper.owner).to eq a
      expect(zuper.receiver).to eq obj
    end

    it 'should be able to find the super method of an unbound method' do
      a = Class.new { def rar; 4; end }
      b = Class.new(a) { def rar; super; end }

      zuper = Pry::Method(b.instance_method(:rar)).super
      expect(zuper.owner).to eq a
    end

    it 'should return nil if no super method exists' do
      a = Class.new { def rar; super; end }

      expect(Pry::Method(a.instance_method(:rar)).super).to eq nil
    end

    it 'should be able to find super methods defined on modules' do
      m = Module.new { def rar; 4; end }
      a = Class.new { def rar; super; end; include m }

      zuper = Pry::Method(a.new.method(:rar)).super
      expect(zuper.owner).to eq m
    end

    it(
      'should be able to find super methods defined on super-classes when ' \
      'there are modules in the way'
    ) do
      a = Class.new { def rar; 4; end }
      m = Module.new { def mooo; 4; end }
      b = Class.new(a) { def rar; super; end; include m }

      zuper = Pry::Method(b.new.method(:rar)).super
      expect(zuper.owner).to eq a
    end

    it 'jumps up multiple levels of bound method, even through modules' do
      a = Class.new { def rar; 4; end }
      m = Module.new { def rar; 4; end }
      b = Class.new(a) { def rar; super; end; include m }

      zuper = Pry::Method(b.new.method(:rar)).super
      expect(zuper.owner).to eq m
      expect(zuper.super.owner).to eq a
    end
  end

  describe 'all_from_class' do
    def should_find_method(name)
      expect(Pry::Method.all_from_class(@class).map(&:name)).to include name
    end

    it 'should be able to find public instance methods defined in a class' do
      @class = Class.new { def meth; 1; end }
      should_find_method('meth')
    end

    it 'finds private and protected instance methods defined in a class' do
      @class = Class.new do
        protected

        def prot; 1; end

        private

        def priv; 1; end
      end
      should_find_method('priv')
      should_find_method('prot')
    end

    it 'should find methods all the way up to Kernel' do
      @class = Class.new
      should_find_method('exit!')
    end

    it 'should be able to find instance methods defined in a super-class' do
      @class = Class.new(Class.new { def meth; 1; end }) {}
      should_find_method('meth')
    end

    it 'finds instance methods defined in modules included into this class' do
      @class = Class.new do
        include(Module.new { def meth; 1; end })
      end
      should_find_method('meth')
    end

    it 'finds instance methods defined in modules included into super-classes' do
      super_class = Class.new do
        include(Module.new { def meth; 1; end })
      end
      @class = Class.new(super_class)
      should_find_method('meth')
    end

    it 'should attribute overridden methods to the sub-class' do
      super_class = Class.new do
        include(Module.new { def meth; 1; end })
      end
      @class = Class.new(super_class) { def meth; 2; end }
      expect(Pry::Method.all_from_class(@class).detect { |x| x.name == 'meth' }.owner)
        .to eq @class
    end

    it 'should be able to find methods defined on a singleton class' do
      @class = (class << Object.new; def meth; 1; end; self; end)
      should_find_method('meth')
    end

    it 'should be able to find methods on super-classes when given a singleton class' do
      @class = (class << Class.new { def meth; 1; end }.new; self; end)
      should_find_method('meth')
    end
  end

  describe 'all_from_obj' do
    describe 'on normal objects' do
      def should_find_method(name)
        expect(Pry::Method.all_from_obj(@obj).map(&:name)).to include name
      end

      it "should find methods defined in the object's class" do
        @obj = Class.new { def meth; 1; end }.new
        should_find_method('meth')
      end

      it "should find methods defined in modules included into the object's class" do
        @obj = Class.new do
          include(Module.new { def meth; 1; end })
        end.new
        should_find_method('meth')
      end

      it "should find methods defined in the object's singleton class" do
        @obj = Object.new
        class << @obj; def meth; 1; end; end
        should_find_method('meth')
      end

      it "should find methods in modules included into the object's singleton class" do
        @obj = Object.new
        @obj.extend(Module.new { def meth; 1; end })
        should_find_method('meth')
      end

      it "should find methods all the way up to Kernel" do
        @obj = Object.new
        should_find_method('exit!')
      end

      it "should not find methods defined on the classes singleton class" do
        @obj = Class.new { class << self; def meth; 1; end; end }.new
        expect(Pry::Method.all_from_obj(@obj).map(&:name)).not_to include 'meth'
      end

      it "should work in the face of an overridden send" do
        @obj = Class.new do
          def meth; 1; end

          def send; raise EOFError; end
        end.new
        should_find_method('meth')
      end
    end

    describe 'on classes' do
      def should_find_method(name)
        expect(Pry::Method.all_from_obj(@class).map(&:name)).to include name
      end

      it "should find methods defined in the class' singleton class" do
        @class = Class.new { class << self; def meth; 1; end; end }
        should_find_method('meth')
      end

      it "should find methods defined on modules extended into the class" do
        @class = Class.new do
          extend(Module.new { def meth; 1; end })
        end
        should_find_method('meth')
      end

      it "should find methods defined on the singleton class of super-classes" do
        @class = Class.new(Class.new { class << self; def meth; 1; end; end })
        should_find_method('meth')
      end

      it "should not find methods defined within the class" do
        @class = Class.new { def meth; 1; end }
        expect(Pry::Method.all_from_obj(@class).map(&:name)).not_to include 'meth'
      end

      it "should find methods defined on Class" do
        @class = Class.new
        should_find_method('allocate')
      end

      it "should find methods defined on Kernel" do
        @class = Class.new
        should_find_method('exit!')
      end

      it "should attribute overridden methods to the sub-class' singleton class" do
        @class = Class.new(Class.new { class << self; def meth; 1; end; end }) do
          class << self; def meth; 1; end; end
        end
        expect(Pry::Method.all_from_obj(@class).detect { |x| x.name == 'meth' }.owner)
          .to eq(class << @class; self; end)
      end

      it "should attrbute overridden methods to the class not the module" do
        @class = Class.new do
          class << self
            def meth; 1; end
          end
          extend(Module.new { def meth; 1; end })
        end
        expect(Pry::Method.all_from_obj(@class).detect { |x| x.name == 'meth' }.owner)
          .to eq(class << @class; self; end)
      end

      it(
        "attributes overridden methods to the relevant singleton class in " \
        "preference to Class"
      ) do
        @class = Class.new { class << self; def allocate; 1; end; end }
        expect(Pry::Method.all_from_obj(@class).detect { |x| x.name == 'allocate' }.owner)
          .to eq(class << @class; self; end)
      end
    end

    describe 'method resolution order' do
      module LS
        class Top; end

        class Next < Top; end

        module M; end
        module N; include M; end
        module O; include M; end
        module P; end

        class Low < Next; include N; include P; end
        class Lower < Low; extend N; end
        class Bottom < Lower; extend O; end
      end

      def eigen_class(obj); class << obj; self; end; end

      it "should look at a class and then its superclass" do
        expect(Pry::Method.instance_resolution_order(LS::Next))
          .to eq [LS::Next] + Pry::Method.instance_resolution_order(LS::Top)
      end

      it "should include the included modules between a class and its superclass" do
        expect(Pry::Method.instance_resolution_order(LS::Low)).to eq(
          [LS::Low, LS::P, LS::N, LS::M] + Pry::Method.instance_resolution_order(LS::Next)
        )
      end

      it "should not include modules extended into the class" do
        expect(Pry::Method.instance_resolution_order(LS::Bottom)).to eq(
          [LS::Bottom] + Pry::Method.instance_resolution_order(LS::Lower)
        )
      end

      it "should include included modules for Modules" do
        expect(Pry::Method.instance_resolution_order(LS::O)).to eq [LS::O, LS::M]
      end

      it "should include the singleton class of objects" do
        obj = LS::Low.new
        expect(Pry::Method.resolution_order(obj)).to eq(
          [eigen_class(obj)] + Pry::Method.instance_resolution_order(LS::Low)
        )
      end

      it "should not include singleton classes of numbers" do
        target_class = 4.class
        expect(Pry::Method.resolution_order(4)).to eq(
          Pry::Method.instance_resolution_order(target_class)
        )
      end

      it "should include singleton classes for classes" do
        expect(Pry::Method.resolution_order(LS::Low)).to eq(
          [eigen_class(LS::Low)] + Pry::Method.resolution_order(LS::Next)
        )
      end

      it "should include modules included into singleton classes" do
        expect(Pry::Method.resolution_order(LS::Lower)).to eq(
          [eigen_class(LS::Lower), LS::N, LS::M] + Pry::Method.resolution_order(LS::Low)
        )
      end

      it "should include modules at most once" do
        expect(Pry::Method.resolution_order(LS::Bottom).count(LS::M)).to eq 1
      end

      it "should include modules at the point which they would be reached" do
        expect(Pry::Method.resolution_order(LS::Bottom)).to eq(
          [eigen_class(LS::Bottom), LS::O] + Pry::Method.resolution_order(LS::Lower)
        )
      end

      it(
        "includes the Pry::Method.instance_resolution_order of Class after " \
        "the singleton classes"
      ) do
        singleton_classes = [
          eigen_class(LS::Top), eigen_class(Object), eigen_class(BasicObject),
          *Pry::Method.instance_resolution_order(Class)
        ]
        expect(Pry::Method.resolution_order(LS::Top)).to eq(singleton_classes)
      end
    end
  end

  describe 'method_name_from_first_line' do
    it 'should work in all simple cases' do
      meth = Pry::Method.new(nil)
      expect(meth.send(:method_name_from_first_line, "def x")).to eq "x"
      expect(meth.send(:method_name_from_first_line, "def self.x")).to eq "x"
      expect(meth.send(:method_name_from_first_line, "def ClassName.x")).to eq "x"
      expect(meth.send(:method_name_from_first_line, "def obj_name.x")).to eq "x"
    end
  end

  describe 'method aliases' do
    before do
      @class = Class.new do
        def eat; end

        alias_method :fress, :eat
        alias_method :omnomnom, :fress

        def eruct; end
      end
    end

    it 'should be able to find method aliases' do
      meth = Pry::Method(@class.new.method(:eat))
      aliases = Set.new(meth.aliases)

      expect(aliases).to eq Set.new(%w[fress omnomnom])
    end

    it 'should return an empty Array if cannot find aliases' do
      meth = Pry::Method(@class.new.method(:eruct))
      expect(meth.aliases).to be_empty
    end

    it 'should not include the own name in the list of aliases' do
      meth = Pry::Method(@class.new.method(:eat))
      expect(meth.aliases).not_to include "eat"
    end

    it 'should find aliases for top-level methods' do
      # top-level methods get added as private instance methods on Object
      class Object
        private

        def my_top_level_method; end
        alias my_other_top_level_method my_top_level_method
      end

      meth = Pry::Method.new(method(:my_top_level_method))
      expect(meth.aliases).to include 'my_other_top_level_method'

      class Object
        remove_method :my_top_level_method
      end
    end

    it 'should be able to find aliases for methods implemented in C' do
      meth = Pry::Method({}.method(:key?))
      aliases = Set.new(meth.aliases)

      expect(aliases).to eq Set.new(["include?", "member?", "has_key?"])
    end
  end

  describe '.signature' do
    before do
      @class = Class.new do
        def self.standard_arg(arg) end

        def self.block_arg(&block) end

        def self.rest(*splat) end

        def self.optional(option = nil) end
      end
    end

    it 'should print the name of regular args' do
      signature = Pry::Method.new(@class.method(:standard_arg)).signature
      expect(signature).to eq("standard_arg(arg)")
    end

    it 'should print the name of block args, with an & label' do
      signature = Pry::Method.new(@class.method(:block_arg)).signature
      expect(signature).to eq("block_arg(&block)")
    end

    it 'should print the name of additional args, with an * label' do
      signature = Pry::Method.new(@class.method(:rest)).signature
      expect(signature).to eq("rest(*splat)")
    end

    it 'should print the name of optional args, with =? after the arg name' do
      signature = Pry::Method.new(@class.method(:optional)).signature
      expect(signature).to eq("optional(option=?)")
    end

    # keyword args are only on >= Ruby 2.1
    if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("2.1")
      it 'should print the name of keyword args, with :? after the arg name' do
        eval <<-RUBY, binding, __FILE__, __LINE__ + 1
          def @class.keyword(keyword_arg: '')
          end
        RUBY
        signature = Pry::Method.new(@class.method(:keyword)).signature
        expect(signature).to eq("keyword(keyword_arg:?)")
      end

      it 'should print the name of keyword args, with : after the arg name' do
        eval <<-RUBY, binding, __FILE__, __LINE__ + 1
          def @class.required_keyword(required_key:)
          end
        RUBY
        signature = Pry::Method.new(@class.method(:required_keyword)).signature
        expect(signature).to eq("required_keyword(required_key:)")
      end
    end
  end

  describe "#owner" do
    context "when it is overriden in Object" do
      before do
        module OwnerMod
          def owner
            :fail
          end
        end

        Object.__send__(:include, OwnerMod)
      end

      after { Object.remove_const(:OwnerMod) }

      it "correctly reports the owner" do
        method = described_class.new(method(:puts))
        expect(method.owner).not_to eq(:fail)
      end
    end
  end

  describe "#parameters" do
    context "when it is overriden in Object" do
      before do
        module ParametersMod
          def parameters
            :fail
          end
        end

        Object.__send__(:include, ParametersMod)
      end

      after { Object.remove_const(:ParametersMod) }

      it "correctly reports the parameters" do
        method = described_class.new(method(:puts))
        expect(method.parameters).not_to eq(:fail)
      end
    end
  end

  describe "#receiver" do
    context "when it is overriden in Object" do
      before do
        module ReceiverMod
          def receiver
            :fail
          end
        end

        Object.__send__(:include, ReceiverMod)
      end

      after { Object.remove_const(:ReceiverMod) }

      it "correctly reports the receiver" do
        method = described_class.new(method(:puts))
        expect(method.receiver).not_to eq(:fail)
      end
    end
  end
end
