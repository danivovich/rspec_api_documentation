module RspecApiDocumentation
  module IndexWriter
    def sections(examples)
      grouped_examples = examples.group_by { |e| (e.api_documentation || {})[:resource_name] }
      resources = grouped_examples.inject([]) do |arr, (resource_name, examples)|
        arr << { :resource_name => resource_name, :examples => examples.sort_by(&:description) }
      end
      resources.sort_by { |resource| resource[:resource_name] }
    end
    module_function :sections
  end
end
