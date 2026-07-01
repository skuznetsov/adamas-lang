require "spec"
require "../../src/compiler/semantic/identity/generic_identity_key"

module GenericIdentityKeySpec
  include Adamas::Compiler::Semantic

  describe "GenericTemplateKey" do
    it "keys by semantic fields rather than display name" do
      source_a = DefIdentity.new(0x100_u64, 7)
      source_b = DefIdentity.new(0x200_u64, 7)

      key_a = GenericTemplateKey.new(
        owner_name: "Outer::Inner",
        template_leaf_name: "Box",
        source_def_identity: source_a,
        declared_type_param_names: ["T"]
      )
      key_b = GenericTemplateKey.new(
        owner_name: "Outer::Inner",
        template_leaf_name: "Box",
        source_def_identity: source_b,
        declared_type_param_names: ["T"]
      )

      key_a.display_name.should eq key_b.display_name
      (key_a == key_b).should be_false

      by_key = {} of GenericTemplateKey => String
      by_key[key_a] = "source-a"
      by_key[key_b] = "source-b"
      by_key.size.should eq 2
      by_key[key_a].should eq "source-a"
      by_key[key_b].should eq "source-b"
    end

    it "hashes equal keys consistently" do
      source = DefIdentity.new(0x100_u64, 7)
      key_a = GenericTemplateKey.new(
        owner_name: "Outer::Inner",
        template_leaf_name: "Box",
        source_def_identity: source,
        declared_type_param_names: ["T"]
      )
      key_b = GenericTemplateKey.new(
        owner_name: "Outer::Inner",
        template_leaf_name: "Box",
        source_def_identity: source,
        declared_type_param_names: ["T"]
      )

      (key_a == key_b).should be_true
      key_a.hash.should eq key_b.hash
    end

    it "keeps declared type parameter names in the key" do
      source = DefIdentity.new(0x100_u64, 8)
      t_param = GenericTemplateKey.new(
        owner_name: "Outer",
        template_leaf_name: "Pair",
        source_def_identity: source,
        declared_type_param_names: ["T", "U"]
      )
      renamed_params = GenericTemplateKey.new(
        owner_name: "Outer",
        template_leaf_name: "Pair",
        source_def_identity: source,
        declared_type_param_names: ["K", "V"]
      )

      (t_param == renamed_params).should be_false
    end

    it "defensively copies declared type parameter arrays" do
      params = ["T"]
      key = GenericTemplateKey.new(
        owner_name: "Owner",
        template_leaf_name: "Box",
        source_def_identity: DefIdentity.new(0x100_u64, 9),
        declared_type_param_names: params
      )

      params << "U"

      key.declared_type_param_names.should eq ["T"]
      key.display_name.should eq "Owner::Box(T)"
    end
  end

  describe "GenericInstanceKey" do
    it "keys instances by template key and specialization argument identities" do
      table = SemanticTypeInternTable.new
      int32 = table.primitive("Int32")
      string = table.primitive("String")
      template = GenericTemplateKey.new(
        owner_name: "Outer",
        template_leaf_name: "Box",
        source_def_identity: DefIdentity.new(0x300_u64, 1),
        declared_type_param_names: ["T"]
      )

      int_instance = GenericInstanceKey.new(
        template_key: template,
        specialization_arg_identities: [int32],
        lexical_context_owner: "UseSite"
      )
      string_instance = GenericInstanceKey.new(
        template_key: template,
        specialization_arg_identities: [string],
        lexical_context_owner: "UseSite"
      )

      (int_instance == string_instance).should be_false
    end

    it "keeps lexical context owner separate from rendered template name" do
      table = SemanticTypeInternTable.new
      int32 = table.primitive("Int32")
      template = GenericTemplateKey.new(
        owner_name: "Outer",
        template_leaf_name: "Box",
        source_def_identity: DefIdentity.new(0x300_u64, 2),
        declared_type_param_names: ["T"]
      )

      in_owner_a = GenericInstanceKey.new(
        template_key: template,
        specialization_arg_identities: [int32],
        lexical_context_owner: "OwnerA"
      )
      in_owner_b = GenericInstanceKey.new(
        template_key: template,
        specialization_arg_identities: [int32],
        lexical_context_owner: "OwnerB"
      )

      in_owner_a.template_key.display_name.should eq in_owner_b.template_key.display_name
      (in_owner_a == in_owner_b).should be_false
    end

    it "defensively copies specialization argument arrays" do
      table = SemanticTypeInternTable.new
      int32 = table.primitive("Int32")
      string = table.primitive("String")
      args = [int32]
      key = GenericInstanceKey.new(
        template_key: GenericTemplateKey.new(
          owner_name: "Owner",
          template_leaf_name: "Box",
          source_def_identity: DefIdentity.new(0x300_u64, 3),
          declared_type_param_names: ["T"]
        ),
        specialization_arg_identities: args
      )

      args << string

      key.specialization_arg_identities.should eq [int32]
    end
  end
end
