# frozen_string_literal: true

if RUBY_ENGINE == 'opal'
  require 'engine/g_1889'
else
  require_relative '../game/base'
end

require_relative 'config'
require_relative 'step/special_track'

module Engine
  module G1889
    class Game < Game::Base
      include G1889::Meta

      register_colors(black: '#37383a',
                      orange: '#f48221',
                      brightGreen: '#76a042',
                      red: '#d81e3e',
                      turquoise: '#00a993',
                      blue: '#0189d1',
                      brown: '#7b352a')

      load_from_json(G1889::Config::JSON)

      GAME_RULES_URL = 'http://dl.deepthoughtgames.com/1889-Rules.pdf'
      GAME_DESIGNER = 'Yasutaka Ikeda (池田 康隆)'
      GAME_INFO_URL = 'https://github.com/tobymao/18xx/wiki/1889'

      EBUY_PRES_SWAP = false # allow presidential swaps of other corps when ebuying
      EBUY_OTHER_VALUE = false # allow ebuying other corp trains for up to face
      HOME_TOKEN_TIMING = :operating_round

      def operating_round(round_num)
        Round::Operating.new(self, [
          Engine::Step::Bankrupt,
          Engine::Step::Exchange,
          G1889::Step::SpecialTrack,
          Engine::Step::BuyCompany,
          Engine::Step::Track,
          Engine::Step::Token,
          Engine::Step::Route,
          Engine::Step::Dividend,
          Engine::Step::DiscardTrain,
          Engine::Step::BuyTrain,
          [Engine::Step::BuyCompany, blocks: true],
        ], round_num: round_num)
      end

      def active_players
        return super if @finished

        company = company_by_id('ER')
        current_entity == company ? [@round.company_sellers[company]] : super
      end
    end
  end
end
