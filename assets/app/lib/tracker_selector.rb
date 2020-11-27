# frozen_string_literal: true

module Lib
  class TrackerSelector
    attr_reader :hex, :tile, :x, :y, :entities, :root

    def initialize(hex, coordinates, root, entities)
      @hex = hex
      @tile = hex.tile
      @x, @y = coordinates
      @root = root
      @entities = entities
    end

    def coordinates
      [@x, @y]
    end
  end
end
