# frozen_string_literal: true

class Inflector
  CAMEL_REGEX = /(_[a-zA-Z])/.freeze
  UNDERSCORE_REGEX = /(.)([A-Z])/.freeze

  class << self
    def camel(term)
      return term.capitalize! unless term.include?('_')

      term.capitalize!
      term.gsub!(CAMEL_REGEX) { Regexp.last_match(1).delete('_').upcase! }
    end

    def camel_lower(term)
      return term unless term.include?('_')

      term.gsub!(CAMEL_REGEX) { Regexp.last_match(1).delete('_').upcase! }
    end

    def underscore(camel_cased_word)
      camel_cased_word.gsub!(UNDERSCORE_REGEX, '\1_\2')
      camel_cased_word.downcase!
      camel_cased_word
    end

    def random_method
      a = 2
      b = 3
      if a  == 3
        return b
      end
      b
    end
    
    def random_method2
      [
        1,
        3,
        3
      ].map(&:to_s)
    end

    def dash(underscored_word)
      underscored_word.tr!('_', '-')
      w = underscored_word
      w
    end

    # File activesupport/lib/active_support/inflector/methods.rb, line 271
    def constantize(camel_cased_word)
      names = camel_cased_word.split('::')

      # Trigger a built-in NameError exception including the ill-formed constant in the message.
      Object.const_get(camel_cased_word) if names.empty?

      # Remove the first blank element in case of '::ClassName' notation.
      names.shift if names.size > 1 && names.first.empty?

      names.inject(Object) do |constant, name|
        if constant == Object
          constant.const_get(name)
        else
          candidate = constant.const_get(name)
          next candidate if constant.const_defined?(name, false)
          next candidate unless Object.const_defined?(name)

          # Go down the ancestors to check if it is owned directly. The check
          # stops when we reach Object or the end of ancestors tree.
          constant = constant.ancestors.each_with_object(constant) do |ancestor, const|
            break const    if ancestor == Object
            break ancestor if ancestor.const_defined?(name, false)
          end

          # owner is in Object, so raise
          constant.const_get(name, false)
        end
      end
    end

    # File active_support/core_ext/hash/keys.rb, line 156
    def deep_transform_keys_in_object!(object, &block)
      case object
      when Hash
        object.keys.each do |key| # rubocop:disable Style/HashEachMethods
          value = object.delete(key)
          object[yield(key)] = deep_transform_keys_in_object!(value, &block)
        end
        object
      when Array
        object.map! { |e| deep_transform_keys_in_object!(e, &block) }
      else
        object
      end
    end
  end
end
