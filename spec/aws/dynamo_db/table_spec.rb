# Copyright 2011-2012 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You
# may not use this file except in compliance with the License. A copy of
# the License is located at
#
#     http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# ANY KIND, either express or implied. See the License for the specific
# language governing permissions and limitations under the License.

require 'spec_helper'

module AWS
  class DynamoDB

    describe Table do

      let(:config) { stub_config }

      let(:client) { config.dynamo_db_client }

      let(:table) { Table.new("MyTable", :config => config) }

      it_should_behave_like "a resource object" do

        let(:identifiers) { ["MyTable"] }

        let(:comparison_instances) { [Table.new("OtherTable")] }

        let(:constructor_args) { ["MyTable"] }

      end

      context '#initialize' do

        it 'should store the name' do
          described_class.new("Foo").name.should == "Foo"
        end

      end

      context 'description' do

        let(:resp) { 
          double("response",
            :request_type => :describe_table,
            :data => { "Table" => response_table }
          )
        }

        let(:response_table) {{ 
          "TableName" => "MyTable",
          "ProvisionedThroughput" => {},
          "KeySchema" => {},
        }}

        let(:attributes) { table.attributes_from_response(resp) }

        context '#exists?' do

          before(:each) { client.stub(:describe_table).and_return(resp) }

          it 'should call describe_table' do
            client.should_receive(:describe_table).
              with(:table_name => "MyTable").
              and_return(resp)
            table.exists?
          end

          it 'should return true if a matching table is found' do
            table.exists?.should be_true
          end

          it 'should return false if no tables are found' do
            client.stub(:describe_table).
              and_raise(Errors::ResourceNotFoundException)
            table.exists?.should == false
          end

        end

        context '#simple_key?' do

          it 'should return true if range_key is nil' do
            table.stub(:range_key).and_return(nil)
            table.simple_key?.should be_true
          end

          it 'should return false if range_key is not nil' do
            table.stub(:range_key).and_return("foo")
            table.simple_key?.should be_false
          end

        end

        context '#composite_key?' do

          it 'should return false if range_key is nil' do
            table.stub(:range_key).and_return(nil)
            table.composite_key?.should be_false
          end

          it 'should return true if range_key is not nil' do
            table.stub(:range_key).and_return("foo")
            table.composite_key?.should be_true
          end

        end

        shared_examples_for "DynamoDB primary key element" do

          let(:key_element) { raise NotImplementedError }

          let(:response_key_element) { {
              "AttributeName" => "Foo",
              "AttributeType" => "N"
            } }

          it 'should include the attribute name' do
            key_element.name.should == "Foo"
          end

          it 'should return the attribute type "N" as :number' do
            key_element.type.should == :number
          end

          it 'should return the attribute type "S" as :string' do
            response_key_element["AttributeType"] = "S"
            key_element.type.should == :string
          end

        end

        shared_examples_for "provides DynamoDB table attributes" do

          it 'should provide the creation_date_time attribute' do
            now = Time.now
            response_table["CreationDateTime"] = Time.now.to_f
            # float equality comparison doesn't work reliably
            attributes[:creation_date_time].should be_within(1).of(now)
          end

          it 'should provide the status attribute' do
            response_table["TableStatus"] = "SOMETHING"
            attributes[:status].should == :something
          end

          context 'hash key attribute' do

            before(:each) do
              response_table["KeySchema"] = {
                "HashKeyElement" => response_key_element
              }
            end

            it_should_behave_like "DynamoDB primary key element" do
              let(:key_element) { attributes[:hash_key] }
            end

          end

          context 'range key attribute' do

            before(:each) do
              response_table["KeySchema"] = {
                "RangeKeyElement" => response_key_element
              }
            end

            it_should_behave_like "DynamoDB primary key element" do
              let(:key_element) { attributes[:range_key] }
            end

          end

          it 'should not provide anything if the table name does not match' do
            response_table["TableName"] = "SomeOtherTable"
            attributes.should be_nil
          end

        end

        shared_examples_for "DynamoDB table attribute accessor" do |attribute|

          before(:each) { client.stub(:describe_table).and_return(resp) }

          it 'should call describe_table' do
            client.should_receive(:describe_table).
              with(:table_name => "MyTable").
              and_return(resp)
            table.send(attribute)
          end

          it 'should return the value from retrieve_attribute' do
            table.stub(:retrieve_attribute).
              and_return("FOO")
            table.send(attribute).should == "FOO"
          end

        end

        context 'from describe_table' do
          it_should_behave_like "provides DynamoDB table attributes"
        end

        context 'from create_table' do
          let(:resp) { double("response",
                              :request_type => :create_table,
                              :data => {
                                "TableDescription" => response_table
                              }) }
          it_should_behave_like "provides DynamoDB table attributes"
        end

        context 'from delete_table' do
          let(:resp) { double("response",
                              :request_type => :delete_table,
                              :data => {
                                "TableDescription" => response_table
                              }) }
          it_should_behave_like "provides DynamoDB table attributes"
        end

        context '#status' do
          it_should_behave_like "DynamoDB table attribute accessor", :status
        end

        context '#creation_date_time' do
          it_should_behave_like "DynamoDB table attribute accessor", :creation_date_time
        end

        context '#hash_key' do
          it_should_behave_like "DynamoDB table attribute accessor", :hash_key
        end

        context '#range_key' do

          it_should_behave_like "DynamoDB table attribute accessor", :range_key

          it 'should not load the schema if the schema is loaded' do
            table.stub(:schema_loaded?).and_return(true)
            client.should_not_receive(:describe_table)
            table.range_key
          end

        end

      end

      context '#schema_loaded?' do

        it 'should return false by default' do
          table.schema_loaded?.should be_false
        end

        it 'should return true when the schema is populated from a response object' do
          table = described_class.new_from(:create_table, {
                                             "TableName" => "MyTable",
                                             "KeySchema" => {
                                               "HashKeyElement" => {
                                                 "AttributeName" => "Foo",
                                                 "AttributeType" => "N"
                                               }
                                             }
                                           }, "MyTable")
          table.schema_loaded?.should be_true
        end

      end

      context '#assert_schema!' do

        it 'should raise an error if the schema is not loaded' do
          table.stub(:schema_loaded?).and_return(false)
          lambda { table.assert_schema! }.
            should raise_error("table schema not loaded")
        end

        it 'should not raise an error if the schema is loaded' do
          table.stub(:schema_loaded?).and_return(true)
          lambda { table.assert_schema! }.should_not raise_error
        end

      end

      context '#load_schema' do

        it 'should call hash_key' do
          table.should_receive(:hash_key)
          table.load_schema
        end

        it 'should return self' do
          table.stub(:hash_key)
          table.load_schema.should be(table)
        end

      end

      shared_examples_for "key element setter" do

        it 'should accept name and type as a hash' do
          lambda { table.send(setter, { "foo" => :string }) }.
            should_not raise_error
        end

        it 'should set the key element' do
          table.send(setter, { "foo" => :string })
          table.send(getter).name.should == "foo"
          table.send(getter).type.should == :string
        end

        it 'should accept symbol attribute names' do
          table.send(setter, { :foo => :string })
          table.send(getter).name.should == "foo"
        end

        it 'should accept the name and type as an array' do
          table.send(setter, [:foo, :string])
          table.send(getter).name.should == "foo"
          table.send(getter).type.should == :string
        end

        it 'should reject multiple hash entries' do
          lambda do
            table.send(setter, {
                         "one" => :string,
                         "two" => :string
                       })
          end.should raise_error(ArgumentError,
                                 "key element may contain only one name/type pair")
        end

        it 'should reject unrecognized type names' do
          lambda { table.send(setter, { "foo" => :bar }) }.
            should raise_error(ArgumentError,
                               "unsupported type :bar")
        end

      end

      context '#hash_key=' do

        let(:setter) { :hash_key= }
        let(:getter) { :hash_key }

        it_should_behave_like "key element setter"

        it 'should cause schema_loaded? to return true' do
          table.hash_key = { "foo" => :string }
          table.schema_loaded?.should be_true
        end

      end

      context '#range_key=' do

        context 'with hash key set' do

          before(:each) { table.hash_key = ["foo", :string] }

          let(:setter) { :range_key= }
          let(:getter) { :range_key }

          it_should_behave_like "key element setter"

        end

        context 'without a configured hash key' do

          it 'should raise an error' do
            table.stub(:schema_loaded?).and_return(false)
            lambda { table.range_key = ["foo", :string] }.
              should raise_error("attempted to set a range key "+
                                 "without configuring a hash key first")
          end

        end

      end

      context '#batch_get' do

        it 'creates a new BatchGet and calls #table on it' do

          attributes = double('attribute-list')
          items = double('items')

          batch = double('batch').as_null_object
          batch.should_receive(:table).with(table.name, attributes, items)
          BatchGet.stub(:new).and_return(batch)

          table.batch_get(attributes, items)

        end

      end

      context '#delete' do

        it 'should call delete_table' do
          client.should_receive(:delete_table).
            with(:table_name => "MyTable")
          table.delete
        end

        it 'should return nil' do
          table.delete.should be_nil
        end

      end

      context '#items' do

        it 'should return an item collection' do
          items = table.items
          items.should be_an(ItemCollection)
          items.config.should be(config)
          items.table.should be(table)
        end

      end

    end

  end
end
