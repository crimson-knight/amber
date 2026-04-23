require "../../spec_helper"

module Amber::Validators
  Validators::Params.compile COMPILED_SIMPLE_DEFINITION do
    required(:name)
    optional(:last_name)
  end

  Validators::Params.compile COMPILED_REQUIRED_DEFINITION do
    required(:name)
    required(:last_name)
  end

  Validators::Params.compile COMPILED_MESSAGE_DEFINITION do
    required(:name, "Name is required")
    required(:nickname, allow_blank: true)
  end

  Validators::Params.compile COMPILED_PREDICATE_DIRECT_DEFINITION do
    required(:age, "Age must be 18+") { |value| value.to_i >= 18 }
    optional(:role, "Role must be admin", allow_blank: false) { |value| value == "admin" }
  end

  PREDICATE_DIRECT_REUSABLE_DEFINITION = Validators::Params.define do
    required(:age, "Age must be 18+") { |value| value.to_i >= 18 }
    optional(:role, "Role must be admin", allow_blank: false) { |value| value == "admin" }
  end

  HYBRID_FIELD_NAME  = "nickname"
  HYBRID_AGE_MESSAGE = "Age must be 18+"

  Validators::Params.compile COMPILED_HYBRID_DEFINITION do
    required(:name)
    optional(HYBRID_FIELD_NAME, "Nickname must be amber", allow_blank: false) { |value| value == "amber" }
    required(:age, HYBRID_AGE_MESSAGE) { |value| value.to_i >= 18 }
    required(:email)
  end

  HYBRID_REUSABLE_DEFINITION = Validators::Params.define do
    required(:name)
    optional(HYBRID_FIELD_NAME, "Nickname must be amber", allow_blank: false) { |value| value == "amber" }
    required(:age, HYBRID_AGE_MESSAGE) { |value| value.to_i >= 18 }
    required(:email)
  end

  MULTI_FALLBACK_ROLE_FIELD       = "role"
  MULTI_FALLBACK_TEAM_FIELD       = "team"
  MULTI_FALLBACK_ROLE_MESSAGE     = "Role must be admin"
  MULTI_FALLBACK_TEAM_MESSAGE     = "Team must be ops"
  MULTI_FALLBACK_CONTACT_MESSAGE  = "Contact must include amber.dev"

  Validators::Params.compile COMPILED_MULTI_FALLBACK_DEFINITION do
    required(:name)
    optional(MULTI_FALLBACK_ROLE_FIELD, MULTI_FALLBACK_ROLE_MESSAGE, allow_blank: false) { |value| value == "admin" }
    required(MULTI_FALLBACK_TEAM_FIELD, MULTI_FALLBACK_TEAM_MESSAGE) { |value| value == "ops" }
    optional(:contact, MULTI_FALLBACK_CONTACT_MESSAGE) { |value| value.includes?("amber.dev") }
  end

  MULTI_FALLBACK_REUSABLE_DEFINITION = Validators::Params.define do
    required(:name)
    optional(MULTI_FALLBACK_ROLE_FIELD, MULTI_FALLBACK_ROLE_MESSAGE, allow_blank: false) { |value| value == "admin" }
    required(MULTI_FALLBACK_TEAM_FIELD, MULTI_FALLBACK_TEAM_MESSAGE) { |value| value == "ops" }
    optional(:contact, MULTI_FALLBACK_CONTACT_MESSAGE) { |value| value.includes?("amber.dev") }
  end

  describe Params do
    describe ".compile" do
      it "reuses compile-time validators across validator instances" do
        first = Validators::Params.new(params_builder("name=elias"))
        second = Validators::Params.new(params_builder("name=elias&last_name=perez"))

        first.validation(COMPILED_SIMPLE_DEFINITION).validate!.should eq({"name" => "elias"})
        second.validation(COMPILED_SIMPLE_DEFINITION).validate!.should eq({"name" => "elias", "last_name" => "perez"})
      end

      it "matches required blank-field behavior without a runtime builder" do
        validator = Validators::Params.new(params_builder("name= &last_name=&middle=j"))
        validator.validation(COMPILED_REQUIRED_DEFINITION)

        validator.valid?.should be_false
        validator.errors.map(&.param).should eq(["name", "last_name"])
      end

      it "supports allow_blank and custom error messages for simple rules" do
        validator = Validators::Params.new(params_builder("name=&nickname="))
        validator.validation(COMPILED_MESSAGE_DEFINITION)

        validator.valid?.should be_false
        validator.errors.map(&.message).should eq(["Name is required"])
      end

      it "matches reusable definition parity for statically knowable predicate rules" do
        compiled_validator = Validators::Params.new(params_builder("age=12&role=user"))
        reusable_validator = Validators::Params.new(params_builder("age=12&role=user"))

        compiled_validator.validation(COMPILED_PREDICATE_DIRECT_DEFINITION)
        reusable_validator.validation(PREDICATE_DIRECT_REUSABLE_DEFINITION)

        compiled_validator.valid?.should be_false
        reusable_validator.valid?.should be_false
        compiled_validator.errors.map(&.message).should eq(reusable_validator.errors.map(&.message))
        compiled_validator.to_h.should eq({"age" => "12", "role" => "user"})
        compiled_validator.to_h.should eq(reusable_validator.to_h)
      end

      it "preserves rule and error ordering for mixed direct and fallback rules" do
        validator = Validators::Params.new(params_builder("name=amber&nickname=user&age=17"))
        validator.validation(COMPILED_HYBRID_DEFINITION)

        validator.valid?.should be_false
        validator.errors.map(&.param).should eq(["nickname", "age", "email"])
        validator.errors.map(&.message).should eq(["Nickname must be amber", HYBRID_AGE_MESSAGE, "Field email is required"])
      end

      it "matches reusable definition parity for mixed direct and fallback rules" do
        compiled_validator = Validators::Params.new(params_builder("name=amber&nickname=amber&age=21&email=amber@example.com"))
        reusable_validator = Validators::Params.new(params_builder("name=amber&nickname=amber&age=21&email=amber@example.com"))

        compiled_result = compiled_validator.validation(COMPILED_HYBRID_DEFINITION).validate!
        reusable_result = reusable_validator.validation(HYBRID_REUSABLE_DEFINITION).validate!

        compiled_result.should eq(reusable_result)
        compiled_result.keys.should eq(["name", HYBRID_FIELD_NAME, "age", "email"])
      end

      it "preserves ordering and params population across multiple opaque fallback rules" do
        compiled_validator = Validators::Params.new(params_builder("name=amber&role=user&team=sales&contact=support@example.com"))
        reusable_validator = Validators::Params.new(params_builder("name=amber&role=user&team=sales&contact=support@example.com"))

        compiled_validator.validation(COMPILED_MULTI_FALLBACK_DEFINITION)
        reusable_validator.validation(MULTI_FALLBACK_REUSABLE_DEFINITION)

        compiled_validator.valid?.should be_false
        reusable_validator.valid?.should be_false
        compiled_validator.errors.map(&.param).should eq(["role", "team", "contact"])
        compiled_validator.errors.map(&.message).should eq(reusable_validator.errors.map(&.message))
        compiled_validator.to_h.should eq({"name" => "amber", "role" => "user", "team" => "sales", "contact" => "support@example.com"})
        compiled_validator.to_h.should eq(reusable_validator.to_h)
      end
    end

    describe ".define" do
      it "reuses compiled rules across validator instances" do
        definition = Validators::Params.define do
          required(:name)
          optional(:last_name)
        end

        first = Validators::Params.new(params_builder("name=elias"))
        second = Validators::Params.new(params_builder("name=elias&last_name=perez"))

        first.validation(definition).validate!.should eq({"name" => "elias"})
        second.validation(definition).validate!.should eq({"name" => "elias", "last_name" => "perez"})
      end

      it "matches required blank-field behavior without a custom predicate" do
        definition = Validators::Params.define do
          required(:name)
          required(:last_name)
        end

        validator = Validators::Params.new(params_builder("name= &last_name=&middle=j"))
        validator.validation(definition)

        validator.valid?.should be_false
        validator.errors.map(&.param).should eq(["name", "last_name"])
      end

      it "preserves custom predicate failures and messages" do
        definition = Validators::Params.define do
          required(:age, "Age must be 18+") { |value| value.to_i >= 18 }
          optional(:role, "Role must be admin", allow_blank: false) { |value| value == "admin" }
        end

        validator = Validators::Params.new(params_builder("age=12&role=user"))
        validator.validation(definition)

        validator.valid?.should be_false
        validator.errors.map(&.message).should eq(["Age must be 18+", "Role must be admin"])
      end
    end

    describe "reusable definition metadata" do
      it "reports counts for compiled definitions with direct predicate specialization" do
        COMPILED_PREDICATE_DIRECT_DEFINITION.total_rule_count.should eq(2)
        COMPILED_PREDICATE_DIRECT_DEFINITION.direct_rule_count.should eq(2)
        COMPILED_PREDICATE_DIRECT_DEFINITION.fallback_rule_count.should eq(0)
        COMPILED_PREDICATE_DIRECT_DEFINITION.hybrid?.should be_false
      end

      it "reports counts for hybrid compiled definitions" do
        COMPILED_HYBRID_DEFINITION.total_rule_count.should eq(4)
        COMPILED_HYBRID_DEFINITION.direct_rule_count.should eq(2)
        COMPILED_HYBRID_DEFINITION.fallback_rule_count.should eq(2)
        COMPILED_HYBRID_DEFINITION.hybrid?.should be_true
      end

      it "reports counts for reusable definitions" do
        HYBRID_REUSABLE_DEFINITION.total_rule_count.should eq(4)
        HYBRID_REUSABLE_DEFINITION.direct_rule_count.should eq(0)
        HYBRID_REUSABLE_DEFINITION.fallback_rule_count.should eq(4)
        HYBRID_REUSABLE_DEFINITION.hybrid?.should be_false
      end
    end

    describe "#validation" do
      context "required params" do
        context "when missing" do
          it "is not valid and has 2 errors" do
            validator = Validators::Params.new(params_builder(""))

            validator.validation do
              required(:name) { true }
              required("last_name") { true }
            end

            validator.valid?.should be_false
            validator.errors.size.should eq 2
          end
        end

        context "when params present" do
          it "is valid and there are no errors" do
            http_params = params_builder("name=elias&last_name=perez&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              required(:name) { |v| !v.nil? }
              required("last_name") { |v| !v.nil? }
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end
        end

        context "when one of the params is invalid" do
          it "is not valid and it has errors" do
            http_params = params_builder("name=&last_name=perez&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              required(:name) { |v| !v.empty? }
              required("last_name") { |v| !v.nil? }
            end

            validator.valid?.should be_false
            validator.errors.size.should eq 1
            validator.errors.first.param.should eq "name"
          end
        end

        context "when no block passed" do
          it "is valid and there are no errors when param is present and not blank" do
            http_params = params_builder("name=elias&last_name=perez&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              required(:name)
              required(:last_name)
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end

          it "is not valid when param is missing" do
            http_params = params_builder("last_name=perez&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              required(:name)
              required(:last_name)
            end

            validator.valid?.should be_false
            validator.errors.size.should eq 1
          end

          it "is not valid when param is present, but blank" do
            http_params = params_builder("name= &last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              required(:name)
              required(:last_name)
            end

            validator.valid?.should be_false
            validator.errors.size.should eq 2
          end

          it "is valid when param is present, but blank, and allow_blank = true" do
            http_params = params_builder("name= &last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              required(:name, allow_blank: true)
              required(:last_name, allow_blank: true)
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end
        end
      end

      context "optional params" do
        context "when block evaluates to true" do
          it "is valid and there are no errors if param is missing" do
            http_params = params_builder("last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              optional(:name) { true }
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end

          it "is valid and there are no errors if param is missing" do
            http_params = params_builder("last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              optional(:name) { true }
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end

          it "is valid and there are no errors when param is present, but blank" do
            http_params = params_builder("name= &last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              optional(:name) { true }
              optional(:last_name) { true }
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end
        end

        context "when block evaluates to false" do
          it "is not valid and it has errors if param is present and not blank" do
            http_params = params_builder("name=asdf")
            validator = Validators::Params.new(http_params)

            validator.validation do
              optional(:name) { false }
            end

            validator.valid?.should be_false
            validator.errors.size.should eq 1
          end

          it "is valid and there are no errors if param is missing" do
            http_params = params_builder("last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              optional(:name) { false }
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end

          it "is valid and there are no errors when param is present, but blank" do
            http_params = params_builder("name=&last_name= &middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              optional(:name) { false }
              optional(:last_name) { false }
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end

          it "is not valid and it has errors when param is present, but blank, and allow_blank = false" do
            http_params = params_builder("name=%20&last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              optional(:name, allow_blank: false) { false }
              optional(:last_name, allow_blank: false) { false }
            end

            validator.valid?.should be_false
            validator.errors.size.should eq 2
          end
        end

        context "when no block passed" do
          it "is valid and there are no errors when param is not present" do
            http_params = params_builder("last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              optional(:name)
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end

          it "is valid and there are no errors when param is present" do
            http_params = params_builder("name=asdf&last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              optional(:name)
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end

          it "is valid and there are no errors when param is present, but blank" do
            http_params = params_builder("name=%20&last_name=&middle=j")
            validator = Validators::Params.new(http_params)

            validator.validation do
              optional(:name)
            end

            validator.valid?.should be_true
            validator.errors.size.should eq 0
          end
        end
      end

      context "casting" do
        it "returns false for the given block" do
          params = params_builder("name=john&number=1&price=3.45&list=[1,2,3]")
          validator = Validators::Params.new(params)
          validator.validation do
            required(:name) { |f| !f.to_s.empty? }
            required(:number) { |f| f.as(String).to_i > 0 }
            required(:price) { |f| f.as(String).to_f == 3.45 }
            required(:list) do |f|
              list = JSON.parse(f.as(String)).as_a
              (list == [1, 2, 3] && !list.includes? 6)
            end
          end

          validator.valid?.should be_truthy
        end
      end
    end

    describe "#valid?" do
      it "returns false with invalid fields" do
        http_params = params_builder("name=john&last_name=doe&middle=j")
        validator = Validators::Params.new(http_params)

        validator.validation do
          required("name") { |v| v.nil? }
          required("last_name") { |v| !v.nil? }
        end

        validator.valid?.should be_false
      end

      it "returns false when key does not exist" do
        http_params = params_builder("name=elias")
        validator = Validators::Params.new(http_params)

        validator.validation do
          required("nonexisting") { |v| !v.nil? }
        end

        validator.valid?.should be_false
      end

      it "returns true with valid fields" do
        http_params = params_builder("name=elias&last_name=perez&middle=j")
        validator = Validators::Params.new(http_params)

        validator.validation do
          required("name") { |v| !v.nil? }
          required("last_name") { |v| !v.nil? }
        end

        validator.valid?.should be_true
      end
    end

    describe "#validate!" do
      it "raises error on failed validation" do
        http_params = params_builder("name=&last_name=&middle=j")
        validator = Validators::Params.new(http_params)

        validator.validation do
          required("name") { |v| !v.to_s.empty? }
          required("last_name") { |v| !v.to_s.empty? }
        end

        expect_raises Exceptions::Validator::ValidationFailed do
          validator.validate!
        end
      end

      it "returns validated params on successful validation" do
        http_params = params_builder("name=elias&last_name=perez&middle=j")
        validator = Validators::Params.new(http_params)
        result : Hash(String, String) = {"name" => "elias", "last_name" => "perez"}

        validator.validation do
          required("name") { |v| !v.nil? }
          required("last_name") { |v| !v.nil? }
        end

        validator.validate!.should eq result
      end

      it "should not present optional fields when param is not present" do
        http_params = params_builder("name=elias&middle=j")
        validator = Validators::Params.new(http_params)
        result : Hash(String, String) = {"name" => "elias"}

        validator.validation do
          required("name") { |v| !v.nil? }
          optional("last_name")
        end

        validator.validate!.should eq result
      end

      it "should present optional fields when param is present" do
        http_params = params_builder("name=elias&last_name=perez&middle=j")
        validator = Validators::Params.new(http_params)
        result : Hash(String, String) = {"name" => "elias", "last_name" => "perez"}

        validator.validation do
          required("name") { |v| !v.nil? }
          optional("last_name")
        end

        validator.validate!.should eq result
      end
    end

    describe "#to_unsafe_h" do
      it "returns request raw_params as a hash" do
        http_params = params_builder("first_name=elias&last_name=perez")
        validator = Validators::Params.new(http_params)

        validator.to_h.should eq({} of String => String)

        validator.to_unsafe_h.should eq({"first_name" => "elias", "last_name" => "perez"})
      end
    end
  end
end
