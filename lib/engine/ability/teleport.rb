# frozen_string_literal: true

require_relative 'tile_lay'

module Engine
  module Ability
    class Teleport < TileLay
      def setup(**_opts)
        super

        @count = 2
        @special = false
        @connect = false
        @blocks = false
        @reachable = false
        @free = false
        @uses_corp_action = true
      end
    end
  end
end
