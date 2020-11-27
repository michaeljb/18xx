# frozen_string_literal: true

require 'view/game/hex'
require 'lib/tile_selector'
require 'lib/token_selector'

module View
  module Game
    class TrackerSelector < TokenSelector
      needs :selected_company, default: nil, store: true

      def render
        entities = @tile_selector.entities
        hex = @tile_selector.hex
        tile = @tile_selector.tile
        coordinates = @tile_selector.coordinates
        root = @tile_selector.root

        logos = list_coordinates(entities, DISTANCE, SIZE).map do |entity, left, bottom|
          click = lambda do
            if entity.company?
              store(:selected_company, entity, skip: true)
            end
            store(:tile_selector, Lib::TileSelector.new(hex, tile, coordinates, root, entity, :map))
          end

          props = {
            attrs: {
              src: entity.logo,
            },
            on: {
              click: click,
            },
            style: style(left, bottom, TOKEN_SIZE, cursor: 'pointer'),
          }

          h(:img, props)
        end

        h(:div, logos)
      end
    end
  end
end
