require "spec_helper"

require "coach"
require "speculation"
require "rack"
require "active_support"
require "active_support/core_ext"

describe "using coach with speculation" do
  context "with some speculation specs defined" do
    S = Speculation

    before do
      S.def :"user/name", String
      S.def :"user/id", String
      S.def :"db/user", S.keys(:req_un => [:"user/name", :"user/id"])
    end

    context "middleware providing data with a key name matching a registered spec" do
      class Authentication < Coach::Middleware
        provides :"db/user"

        def call
          user = params[:user_injected_from_test]
          provide(:"db/user" => user.symbolize_keys)
          next_middleware.call
        end
      end

      class HelloUser < Coach::Middleware
        uses Authentication
        requires :"db/user"

        def call
          [ 200, {}, [ "hello #{user[:name]}" ] ]
        end
      end

      def env_with_params(params)
        {
          "rack.input" => StringIO.new(""), # active support blows up when this isn't provided
          "QUERY_STRING" => Rack::Utils.build_nested_query(params)
        }
      end

      context "with S.check_asserts on" do
        before { S.check_asserts = true }

        context "when providing invalid data according to registered spec" do
          it "blows up" do
            user = {
              name: "Jamie",
              id: ["123"], # this isn't valid!
            }
            env = env_with_params(user_injected_from_test: user)
            handler = Coach::Handler.new(HelloUser)

            expect { handler.call(env) }.to raise_error(S::Error, <<EOS)
Spec assertion failed
In: [:id] val: ["123"] fails spec: :"user/id" at: [:id] predicate: [String, [["123"]]]
:spec Speculation::HashSpec(db/user)
:value {:name=>"Jamie", :id=>["123"]}
:failure :assertion_failed
EOS
          end
        end

        context "when providing valid data according to spec" do
          it "doesn't blow up" do
            user = { name: "Jamie", id: "123" }

            handler = Coach::Handler.new(HelloUser)
            env = env_with_params(user_injected_from_test: user)

            resp = handler.call(env)

            expect(resp).to eq([200, {}, ["hello Jamie"]])
          end
        end

        context "demonstrate data generation" do
          it "let's us to property based tests, or just avoid having to come up with fake data" do
            require 'speculation/gen'
            user = S::Gen.generate(S.gen(:"db/user"))

            handler = Coach::Handler.new(HelloUser)
            env = env_with_params(user_injected_from_test: user)

            resp = handler.call(env)

            response_spec = S.tuple(Integer, Hash, S.tuple(/^hello/))
            expect(S.valid?(response_spec, resp)).to be(true), S.explain_str(response_spec, resp)

            # to make this fail:
            #   response_spec = S.tuple(Integer, Hash, /^hello/)
            #   expect(S.valid?(response_spec, resp)).to be(true), S.explain_str(response_spec, resp)
            # we'd get:
            #   Failure/Error: expect(S.valid?(response_spec, resp)).to be(true), S.explain_str(response_spec, resp)
            #
            #     In: [2] val: ["hello H"] fails at: [2] predicate: [/^hello/, [["hello H"]]]
            #     :spec Speculation::TupleSpec()
            #     :value [200, {}, ["hello H"]]
          end
        end
      end

      context "with S.check_asserts off" do
        before { S.check_asserts = false }

        it "doesn't blow up" do
          user = {
            name: "Jamie",
            id: ["123"] # this is invalid!
          }
          env = env_with_params(user_injected_from_test: user)
          handler = Coach::Handler.new(HelloUser)

          resp = handler.call(env)

          expect(resp).to eq([200, {}, ["hello Jamie"]])
        end
      end
    end
  end
end
