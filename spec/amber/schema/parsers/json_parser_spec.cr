require "../../../spec_helper"

module Amber::Schema::Parser
  describe JSONParser do
    describe ".parse_string" do
      it "parses empty string to empty hash" do
        result = JSONParser.parse_string("")
        result.should eq({} of String => JSON::Any)
      end

      it "parses simple JSON object" do
        json = %({"name": "John", "age": 30})
        result = JSONParser.parse_string(json)
        
        result["name"].as_s.should eq("John")
        result["age"].as_i.should eq(30)
      end

      it "parses nested JSON objects" do
        json = %({"user": {"name": "John", "address": {"city": "NYC", "zip": "10001"}}})
        result = JSONParser.parse_string(json)
        
        result["user"].as_h["name"].as_s.should eq("John")
        result["user"].as_h["address"].as_h["city"].as_s.should eq("NYC")
      end

      it "parses JSON arrays" do
        json = %({"tags": ["ruby", "crystal", "amber"]})
        result = JSONParser.parse_string(json)
        
        tags = result["tags"].as_a
        tags.size.should eq(3)
        tags[0].as_s.should eq("ruby")
      end

      it "wraps root array in data key" do
        json = %([{"id": 1}, {"id": 2}])
        result = JSONParser.parse_string(json)
        
        result.has_key?("data").should be_true
        result["data"].as_a.size.should eq(2)
      end

      it "wraps primitive value in value key" do
        json = %("hello")
        result = JSONParser.parse_string(json)
        
        result.has_key?("value").should be_true
        result["value"].as_s.should eq("hello")
      end

      it "raises SchemaDefinitionError for invalid JSON" do
        expect_raises(SchemaDefinitionError, "Invalid JSON") do
          JSONParser.parse_string("{invalid json}")
        end
      end
    end

    describe ".parse_params" do
      it "parses simple parameters" do
        params = HTTP::Params.parse("name=John&age=30")
        result = JSONParser.parse_params(params)
        
        result["name"].as_s.should eq("John")
        result["age"].as_i.should eq(30)
      end

      it "parses array parameters with []" do
        params = HTTP::Params.parse("tags[]=ruby&tags[]=crystal")
        result = JSONParser.parse_params(params)
        
        result["tags"].as_a.map(&.as_s).should eq(["ruby", "crystal"])
      end

      it "parses nested parameters with bracket notation" do
        params = HTTP::Params.parse("user[name]=John&user[age]=30")
        result = JSONParser.parse_params(params)
        
        result["user"].as_h["name"].as_s.should eq("John")
        result["user"].as_h["age"].as_i.should eq(30)
      end

      it "parses deeply nested parameters" do
        params = HTTP::Params.parse("user[address][city]=NYC&user[address][zip]=10001")
        result = JSONParser.parse_params(params)
        
        result["user"].as_h["address"].as_h["city"].as_s.should eq("NYC")
        result["user"].as_h["address"].as_h["zip"].as_i.should eq(10001)
      end

      it "parses boolean values" do
        params = HTTP::Params.parse("active=true&admin=false")
        result = JSONParser.parse_params(params)
        
        result["active"].as_bool.should be_true
        result["admin"].as_bool.should be_false
      end

      it "parses numeric values" do
        params = HTTP::Params.parse("int=42&float=3.14&negative=-10")
        result = JSONParser.parse_params(params)
        
        result["int"].as_i.should eq(42)
        result["float"].as_f.should eq(3.14)
        result["negative"].as_i.should eq(-10)
      end

      it "parses null values" do
        params = HTTP::Params.parse("value=null")
        result = JSONParser.parse_params(params)
        
        result["value"].as_nil.should be_nil
      end

      it "handles empty values as nil" do
        params = HTTP::Params.parse("value=")
        result = JSONParser.parse_params(params)
        
        result["value"].as_nil.should be_nil
      end
    end

    describe ".parse_multipart" do
      it "parses string values" do
        params = {"name" => "John", "age" => "30"}
        result = JSONParser.parse_multipart(params)
        
        result["name"].as_s.should eq("John")
        result["age"].as_i.should eq(30)
      end

      it "parses array values" do
        params = {"tags" => ["ruby", "crystal"]}
        result = JSONParser.parse_multipart(params)
        
        result["tags"].as_a.map(&.as_s).should eq(["ruby", "crystal"])
      end

      it "handles array notation in keys" do
        params = {"tags[]" => ["ruby", "crystal"]}
        result = JSONParser.parse_multipart(params)
        
        result["tags"].as_a.map(&.as_s).should eq(["ruby", "crystal"])
      end
    end

    describe "dot notation support" do
      it "parses dot notation keys" do
        params = HTTP::Params.parse("user.name=John&user.address.city=NYC")
        result = JSONParser.parse_params(params)
        
        result["user"].as_h["name"].as_s.should eq("John")
        result["user"].as_h["address"].as_h["city"].as_s.should eq("NYC")
      end
    end

    describe "JSON in query strings" do
      it "parses embedded JSON objects" do
        params = HTTP::Params.parse("data=%7B%22name%22%3A%22John%22%7D")  # URL encoded {"name":"John"}
        result = JSONParser.parse_params(params)
        
        result["data"].as_h["name"].as_s.should eq("John")
      end

      it "parses embedded JSON arrays" do
        params = HTTP::Params.parse("data=%5B1%2C2%2C3%5D")  # URL encoded [1,2,3]
        result = JSONParser.parse_params(params)
        
        result["data"].as_a.map(&.as_i).should eq([1, 2, 3])
      end
    end

    describe "field aliasing" do
      # Skip field aliasing test for now - requires more complex setup
      pending "extracts fields with aliasing when schema provided"
    end

    describe "error handling" do
      it "provides detailed error for JSON parse failures" do
        json = %({
          "name": "John",
          "age": 30,
          "invalid": true,
        })
        
        expect_raises(SchemaDefinitionError) do
          JSONParser.parse_string(json)
        end
      end

      # Array index notation requires more complex parsing
      pending "handles array index notation"
    end

    describe "type coercion" do
      it "coerces string numbers to numeric types" do
        params = HTTP::Params.parse("int=42&float=3.14&sci=1.23e-4")
        result = JSONParser.parse_params(params)
        
        result["int"].as_i.should eq(42)
        result["float"].as_f.should eq(3.14)
        result["sci"].as_f.should be_close(0.000123, 0.000001)
      end

      it "handles various boolean representations" do
        params = HTTP::Params.parse("t1=true&t2=True&t3=TRUE&f1=false&f2=False&f3=FALSE")
        result = JSONParser.parse_params(params)
        
        result["t1"].as_bool.should be_true
        result["t2"].as_bool.should be_true
        result["t3"].as_bool.should be_true
        result["f1"].as_bool.should be_false
        result["f2"].as_bool.should be_false
        result["f3"].as_bool.should be_false
      end
    end
  end
end