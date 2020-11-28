# frozen_string_literal: true

require_relative 'base'

module Engine
  module Ability
    class TileLay < Base
      attr_reader :hexes, :tiles, :free, :discount, :special, :connect, :blocks,
                  :reachable, :must_lay_together, :cost, :uses_corp_action

      def setup(tiles:, hexes: nil, free: false, discount: nil, special: nil,
                connect: nil, blocks: nil, reachable: nil,
                must_lay_together: false, cost: 0, uses_corp_action: nil)
        @hexes = hexes
        @tiles = tiles
        @free = free
        @discount = discount || 0
        @special = special.nil? ? true : special
        @connect = connect.nil? ? true : connect
        @blocks = blocks.nil? ? true : blocks
        @reachable = !!reachable
        @must_lay_together = must_lay_together
        @cost = cost
        @uses_corp_action = !!uses_corp_action
      end
    end
  end
end
