# frozen_string_literal: true

require_relative 'entity/base'

module BrightSerializer
  class Attribute
    attr_reader :key, :block, :condition, :entity
    attr_accessor :transformed_key

    def initialize(key, condition, entity, &block)
      @key = key
      @condition = condition
      @block = block
      @entity = entity ? Entity::Base.new(entity) : nil
    end

    def serialize(object, params)
      return unless object

      value =
        if @block
          @block.arity.abs == 1 ? object.instance_eval(&@block) : object.instance_exec(object, params, &@block)
        elsif object.is_a?(Hash)
          object[key]
        else
          object.send(key)
        end

      value.respond_to?(:serializable_hash) ? value.serializable_hash : value
    end

    def condition?(object, params)
      return true unless @condition

      r = @condition.call(object, params)
      return r
    end

    def untested_method1
      2 + 2 == 4
    end
  end
end
