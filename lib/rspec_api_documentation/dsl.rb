require 'rack/test/methods'
require 'rack'
require 'webmock'
require 'cgi'

module RspecApiDocumentation
  module DSL
    extend ActiveSupport::Concern

    module ClassMethods
      def self.define_action(method)
        define_method method do |*args, &block|
          options = if args.last.is_a?(Hash) then args.pop else {} end
          options[:api_documentation] ||= {}
          options[:api_documentation][:method] = method
          options[:api_documentation][:path] = args.first
          args.push(options)
          args[0] = "#{method.to_s.upcase} #{args[0]}"
          context(*args, &block)
        end
      end

      define_action :get
      define_action :post
      define_action :put
      define_action :delete

      def parameter(name, description, options = {})
        parameters.push(options.merge(:name => name.to_s, :description => description))
      end

      def required_parameters(*names)
        names.each do |name|
          param = parameters.find { |param| param[:name] == name.to_s }
          raise "Undefined parameters can not be required." unless param
          param[:required] = true
        end
      end

      def callback(description, &block)
        self.send(:include, WebMock::API)
        context(description, &block)
      end

      def trigger_callback(&block)
        define_method(:do_callback) do
          stub_request(:any, callback_url).to_rack(destination)
          instance_eval &block
        end
      end

      def scope_parameters(scope, keys)
        return unless api_metadata[:parameters]

        if keys == :all
          keys = parameter_keys.map(&:to_s)
        else
          keys = keys.map(&:to_s)
        end

        keys.each do |key|
          param = parameters.detect { |param| param[:name] == key }
          param[:scope] = scope if param
        end
      end

      def example_request(description, params = {}, &block)
        example(description) do
          do_request(params)
          instance_eval &block if block_given?
        end
      end

      private
      def parameters
        api_metadata[:parameters] ||= []
        if superclass_api_metadata && api_metadata[:parameters].equal?(superclass_api_metadata[:parameters])
          api_metadata[:parameters] = Marshal.load(Marshal.dump(superclass_api_metadata[:parameters]))
        end
        api_metadata[:parameters]
      end

      def parameter_keys
        parameters.map { |param| param[:name] }
      end

      def api_metadata
        metadata[:api_documentation] ||= {}
      end

      def superclass_api_metadata
        return nil unless superclass_metadata
        superclass_metadata[:api_documentation]
      end
    end

    module InstanceMethods
      def client
        @client ||= TestClient.new(self)
      end

      def destination
        @destination ||= TestServer.new(self)
      end

      def callback_url
        raise "You must define callback_url"
      end

      def do_request(extra_params = {})
        @extra_params = extra_params
        params_or_body = nil
        path_or_query = path

        if method == :get && !query_string.blank?
          path_or_query = path + "?#{query_string}"
        else
          params_or_body = respond_to?(:raw_post) ? raw_post : params
        end

        client.send(method, path_or_query, params_or_body)
      end

      def query_string
        query = params.to_a.map do |param|
          param.map! { |a| CGI.escape(a.to_s) }
          param.join("=")
        end
        query.join("&")
      end

      def params
        return unless example_api_metadata[:parameters]
        parameters = example_api_metadata[:parameters].inject({}) do |hash, param|
          set_param(hash, param)
        end
        parameters.merge!(extra_params)
        parameters
      end

      def method
        example_api_metadata[:method]
      end

      def in_path?(param)
        path_params.include?(param)
      end

      def path_params
        example_api_metadata[:path].scan(/:(\w+)/).flatten
      end

      def path
        example_api_metadata[:path].gsub(/:(\w+)/) do |match|
          if respond_to?($1)
            send($1)
          else
            match
          end
        end
      end

      def app
        RspecApiDocumentation.configuration.app
      end

      def explanation(text)
        example_api_metadata[:explanation] = text
      end

      def status
        last_response.status
      end

      def response_body
        last_response.body
      end

      private
      def extra_params
        return {} if @extra_params.nil?
        @extra_params.inject({}) do |h, (k, v)|
          h[k.to_s] = v
          h
        end
      end

      def set_param(hash, param)
        key = param[:name]
        return hash if !respond_to?(key) || in_path?(key)

        if param[:scope]
          hash[param[:scope].to_s] ||= {}
          hash[param[:scope].to_s][key] = send(key)
        else
          hash[key] = send(key)
        end

        hash
      end

      def example_api_metadata
        example.metadata[:api_documentation] ||= {}
      end
    end
  end
end

def self.resource(*args, &block)
  options = if args.last.is_a?(Hash) then args.pop else {} end
  options[:api_documentation] ||= {}
  options[:api_docs_dsl] = true
  options[:api_documentation][:resource_name] = args.first
  options[:api_documentation][:document] = true
  args.push(options)
  describe(*args, &block)
end

RSpec.configuration.include RspecApiDocumentation::DSL, :api_docs_dsl => true
RSpec.configuration.include Rack::Test::Methods, :api_docs_dsl => true
