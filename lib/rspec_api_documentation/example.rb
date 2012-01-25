module RspecApiDocumentation
  class Example
    attr_reader :example, :configuration

    def initialize(example, configuration)
      @example = example
      @configuration = configuration
    end

    def method_missing(method_sym, *args, &block)
      if api_metadata.has_key?(method_sym)
        api_metadata[method_sym]
      else
        example.send(method_sym, *args, &block)
      end
    end

    def respond_to?(method_sym, include_private = false)
      super || api_metadata.has_key?(method_sym) || example.respond_to?(method_sym, include_private)
    end

    def method
      api_metadata[:method]
    end

    def should_document?
      return false if pending? || !api_metadata[:resource_name] || !api_metadata[:document]
      return true if configuration.filter == :all
      return false if (Array(api_metadata[:document]) & Array(configuration.exclusion_filter)).length > 0
      return true if (Array(api_metadata[:document]) & Array(configuration.filter)).length > 0
    end

    def public?
      api_metadata[:public]
    end

    def has_parameters?
      respond_to?(:parameters) && parameters.present?
    end

    def explanation
      api_metadata[:explanation] || nil
    end

    def requests
      api_metadata[:requests] || []
    end

    def api_metadata
      example.metadata[:api_documentation] ||= {}
    end
  end
end
