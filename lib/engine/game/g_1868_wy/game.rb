# frozen_string_literal: true

require_relative 'entities'
require_relative 'map'
require_relative 'meta'
require_relative 'trains'
require_relative 'step/boom_track'
require_relative 'step/buy_company'
require_relative 'step/buy_train'
require_relative 'step/development_token'
require_relative 'step/dividend'
require_relative 'step/route'
require_relative 'step/token'
require_relative 'step/track'
require_relative 'step/waterfall_auction'
require_relative '../base'
require_relative '../company_price_up_to_face'
require_relative '../stubs_are_restricted'

module Engine
  module Game
    module G1868WY
      class Game < Game::Base
        include_meta(G1868WY::Meta)
        include Entities
        include Map
        include Trains

        include CompanyPriceUpToFace
        include StubsAreRestricted

        attr_reader :tile_layers

        BANK_CASH = 99_999
        STARTING_CASH = { 3 => 734, 4 => 550, 5 => 440, 6 => 367 }.freeze
        CERT_LIMIT = { 3 => 20, 4 => 15, 5 => 12, 6 => 10 }.freeze

        POOL_SHARE_DROP = :each
        CAPITALIZATION = :incremental
        SELL_BUY_ORDER = :sell_buy
        HOME_TOKEN_TIMING = :par

        TRACK_POINTS = 6
        YELLOW_POINT_COST = 2
        UPGRADE_POINT_COST = 3

        MUST_EMERGENCY_ISSUE_BEFORE_EBUY = true
        MUST_BUY_TRAIN = :always

        MARKET = [
          %w[64 68 72 76 82 90 100p 110 120 140 160 180 200 225 250 275 300 325 350 375 400 430 460 490 525 560],
          %w[60y 64 68 72 76 82 90p 100 110 120 140 160 180 200 225 250 275 300 325 350 375 400 430 460 490 525],
          %w[55y 60y 64 68 72 76 82p 90 100 110 120 140 160 180 200 225 250 275 300 325],
          %w[50o 55y 60y 64 68 72 76p 82 90 100 110 120 140 160 180 200],
          %w[40o 50o 55y 60y 64 68 72p 76 82 90 100 110 120],
          %w[30b 40o 50o 55y 60y 64 68p 72 76 82 90],
          %w[20b 30b 40o 50o 55y 60y 64 68 72],
          ['', '20b', '30b', '40o', '50o', '55y', '60y'],
        ].freeze

        LATE_CORPORATIONS = %w[C&N DPR FEMV LNP OSL].freeze
        EVENTS_TEXT = Base::EVENTS_TEXT.merge(
          'all_corps_available' => ['All Corporations Available',
                                    'C&N, DPR, FEMV, LNP, OSL are now available to start'],
          'full_capitalization' =>
            ['Full Capitalization', 'Railroads now float at 60% and receive full capitalization'],
        ).freeze
        STATUS_TEXT = Base::STATUS_TEXT.merge(
          'all_corps_available' => ['All Corporations Available',
                                    'C&N, DPR, FEMV, LNP, OSL are available to start'],
          'full_capitalization' =>
            ['Full Capitalization', 'Railroads float at 60% and receive full capitalization'],
        ).freeze

        BROWN_DOUBLE_BOOMCITY_TILE = 'B5BB'
        GRAY_BOOMCITY_TILE = '5B'
        GRAY_DOUBLE_BOOMCITY_TILE = '5BB'

        DTC_BOOMCITY = 3
        DTC_REVENUE = 4
        DTC_DOUBLE_BOOMCITY = 5

        BOOMING_REVENUE_BONUS = 10

        def dotify(tile)
          tile.towns.each { |town| town.style = :dot }
          tile
        end

        def init_tiles
          super.each { |tile| dotify(tile) }
        end

        def init_hexes(companies, corporations)
          super.each { |hex| dotify(hex.tile) }
        end

        def add_extra_tile(tile)
          dotify(super)
        end

        def ipo_name(_entity = nil)
          'Treasury'
        end

        def setup
          init_track_points
          setup_company_price_up_to_face

          @development_hexes = init_development_hexes
          @development_token_count = Hash.new(0)
          @pending_boom_tile_lays = {}
          @pending_gray_boom_tile_lays = { boom: [], double_boom: [] }

          @tile_layers = {}

          @late_corps, @corporations = @corporations.partition { |c| LATE_CORPORATIONS.include?(c.id) }
          @late_corps.each { |corp| corp.reservation_color = nil }

          @coal_companies = init_coal_companies
          @minors.concat(@coal_companies)
          update_cache(:minors)
        end

        def operating_round(round_num)
          G1868WY::Round::Operating.new(self, [
            G1868WY::Step::BoomTrack,
            G1868WY::Step::DevelopmentToken,
            Engine::Step::Bankrupt,
            Engine::Step::Exchange,
            Engine::Step::SpecialTrack,
            G1868WY::Step::BuyCompany,
            G1868WY::Step::Track,
            G1868WY::Step::Token,
            G1868WY::Step::Route,
            G1868WY::Step::Dividend,
            Engine::Step::DiscardTrain,
            G1868WY::Step::BuyTrain,
            [G1868WY::Step::BuyCompany, { blocks: true }],
          ], round_num: round_num)
        end

        def new_auction_round
          Engine::Round::Auction.new(self, [
            Engine::Step::CompanyPendingPar,
            G1868WY::Step::WaterfallAuction,
          ])
        end

        def init_round_finished
          p10_company.revenue = 0
          p10_company.desc = 'Pays $40 revenue ONLY in green phases. Closes, '\
                             'becomes LHP train at phase 5.'

          p11_company.close!
          @log << "#{p11_company.name} closes"
        end

        def event_all_corps_available!
          @late_corps.each { |corp| corp.reservation_color = CORPORATION_RESERVATION_COLOR }
          @corporations.concat(@late_corps)
          @log << '-- All corporations now available --'
        end

        def event_full_capitalization!
          @log << '-- Event: Railroads now float at 60% and receive full capitalization --'
          @corporations.each do |corporation|
            next if corporation.floated?

            corporation.capitalization = :full
            corporation.float_percent = 60
          end
        end

        def float_corporation(corporation)
          if @phase.status.include?('full_capitalization')
            bundle = ShareBundle.new(corporation.shares_of(corporation))
            @share_pool.transfer_shares(bundle, @share_pool)
            @log << "#{corporation.name}'s remaining shares are transferred to the Market"
          end

          super

          corporation.capitalization = :incremental
        end

        def init_track_points
          @track_points_used = Hash.new(0)
        end

        def status_str(corporation)
          return unless corporation.floated?

          if corporation.minor?
            player = corporation.owner
            "#{player.name} Cash: #{format_currency(player.cash)}"
          else
            "Track Points: #{track_points_available(corporation)}"
          end
        end

        def p1_company
          @p1_company ||= company_by_id('P1')
        end

        def p7_company
          @p7_company ||= company_by_id('P7')
        end

        def p10_company
          @p10_company ||= company_by_id('P10')
        end

        def p11_company
          @p11_company ||= company_by_id('P11')
        end

        def p12_company
          @p12_company ||= company_by_id('P12')
        end

        def track_points_available(entity)
          return 0 unless (corporation = entity).corporation?

          p7_point = p7_company.owner == corporation ? 1 : 0
          TRACK_POINTS + p7_point - @track_points_used[corporation]
        end

        def tile_lays(entity)
          if (points = track_points_available(entity)) >= UPGRADE_POINT_COST
            { @round.num_laid_track => { lay: true, upgrade: true, cost: 0 } }
          elsif points == YELLOW_POINT_COST
            { @round.num_laid_track => { lay: true, upgrade: false, cost: 0 } }
          else
            []
          end
        end

        def spend_tile_lay_points(action)
          return unless (corporation = action.entity).corporation?

          points_used = action.tile.color == :yellow ? YELLOW_POINT_COST : UPGRADE_POINT_COST
          @track_points_used[corporation] += points_used
        end

        def or_round_finished
          init_track_points
        end

        def action_processed(action)
          case action
          when Action::LayTile
            if action.hex.name == 'G15'
              action.hex.tile.color = :gray
              @log << 'Wind River Canyon turns gray; it can never be upgraded'
            end
            @tile_layers[action.hex] = action.entity.player
          end
        end

        def or_set_finished
          depot.export!
        end

        def isr_payout_companies(p12_bidders)
          payout_companies

          return if p12_bidders.empty?

          bidders = p12_bidders.map(&:name).sort
          @log << "#{bidders.join(', ')} collect#{bidders.one? ? 's' : ''} $5 "\
                  "for their bid#{bidders.one? ? '' : 's'} on #{p12_company.name}"
          p12_bidders.each { |p| @bank.spend(5, p) }
        end

        def isr_company_choices
          @isr_company_choices ||= COMPANY_CHOICES.transform_values do |company_ids|
            company_ids.map { |id| company_by_id(id) }
          end
        end

        def init_coal_companies
          @players.map.with_index do |player, index|
            coal_company = Engine::Minor.new(
              type: :coal,
              sym: "Coal-#{index + 1}",
              name: "#{player.name} Coal",
              logo: '1868_wy/coal',
              tokens: [],
              color: :black,
              abilities: [{ type: 'no_buy', owner_type: 'player' }],
            )
            coal_company.owner = player
            coal_company.float!
            coal_company
          end
        end

        def init_development_hexes
          @hexes.select do |hex|
            !%i[gray red].include?(hex.tile.color) && hex.tile.city_towns.empty? && hex.tile.offboards.empty?
          end
        end

        def operating_order
          coal = @coal_companies.sort_by { |m| @players.index(m.owner) }
          railroads = @corporations.select(&:floated?).sort
          coal + railroads
        end

        def setup_development_tokens
          logo = "/icons/1868_wy/coal-#{@phase.name}.svg"
          @coal_companies.each do |coal|
            coal.unplaced_tokens.each { |t| coal.tokens.delete(t) }
            (@phase.name == '2' ? 2 : 1).times do
              coal.tokens << Token.new(
                coal,
                price: 0,
                logo: logo,
                simple_logo: logo,
                type: :development,
              )
            end
          end
        end

        def available_coal_hex?(hex)
          (hex.tile.icons.count { |i| i.name == :coal } < 2) && @development_hexes.include?(hex)
        end

        def place_development_token(action)
          entity = action.entity
          player = entity.player
          hex = action.hex
          token = action.token
          cost = action.cost

          player.spend(cost, @bank) if cost.positive?
          token.place(nil, hex: hex)
          hex.tile.icons << Part::Icon.new("1868_wy/coal-#{@phase.name}", :coal)

          cost_str = cost.positive? ? " for #{format_currency(cost)}" : ''
          @log << "#{player.name} places a Development Token on #{hex.name}#{cost_str}"

          increment_development_token_count(hex)
        end

        def boomer?(tile)
          tile.city_towns.any?(&:boom)
        end

        def increment_development_token_count(tokened_hex)
          hexes = [tokened_hex].concat((0..5).map { |edge| hex_neighbor(tokened_hex, edge) })

          hexes.each do |hex|
            next unless hex
            next unless boomer?(hex.tile)

            @development_token_count[hex] += 1
            handle_boom!(hex)
          end

          # gray tiles are limited, so handle them last
          handle_gray_booms!
        end

        def handle_boom!(hex)
          case @development_token_count[hex]
          when DTC_BOOMCITY
            boomtown_to_boomcity!(hex)
          when DTC_REVENUE
            boomcity_increase_revenue!(hex)
          when DTC_DOUBLE_BOOMCITY
            boomcity_to_double_boomcity!(hex) if %i[brown gray].include?(hex.tile.color)
          end
        end

        def boomtown_to_boomcity!(hex, gray_checked: false)
          if !gray_checked && hex.tile.color == :gray
            @pending_gray_boom_tile_lays[:boom] << hex
            return
          end

          @log << "#{location_name(hex.name)} (#{hex.name}) is Booming! A Boomtown is replaced by a Boom City."

          # auto-upgrade the preprinted tile
          if (tile = hex.tile).preprinted
            boomtown = tile.towns.pop
            city = Engine::Part::City.new('0', boom: true, loc: boomtown.loc)
            city.tile = tile
            tile.cities << city
            tile.city_towns << city
            tile.rotate!(0) # reset tile rendering

          # more than one Boomtown in yellow, a choice must be made
          elsif tile.towns.count(&:boom) > 1 && tile.color == :yellow
            @pending_boom_tile_lays[hex] = boomcity_tiles(tile.name)

          # auto-upgrade the tile
          else
            new_tile = boomcity_tiles(tile.name).first
            boom_autoreplace_tile!(new_tile, tile)
          end
        end

        def boomcity_increase_revenue!(hex)
          # actual logic for increased revenue is handled in `revenue_for()`
          @log << "#{location_name(hex.name)} (#{hex.name}) is Booming! Its revenue "\
                  "increases by #{format_currency(BOOMING_REVENUE_BONUS)}."
        end

        def boomcity_to_double_boomcity!(hex, gray_checked: false)
          if !gray_checked && hex.tile.color == :gray
            @pending_gray_boom_tile_lays[:double_boom] << hex
            return
          end

          @log << "#{location_name(hex.name)} (#{hex.name}) is Booming! The Boom City becomes a Double Boom City."

          tile = hex.tile
          new_tile = double_boomcity_tile(tile.name)
          boom_autoreplace_tile!(new_tile, tile)
        end

        def boom_autoreplace_tile!(new_tile, tile)
          hex = tile.hex

          new_tile.rotate!(tile.rotation)
          update_tile_lists(new_tile, tile)
          hex.lay(new_tile)
          @log << "#{new_tile.name} replaces #{tile.name} on #{hex.name}"
        end

        def gray_double_boomcity_tile_count
          @tiles.count { |t| t.name == GRAY_DOUBLE_BOOMCITY_TILE }
        end

        def gray_boomcity_tile_count
          @tiles.count { |t| t.name == GRAY_BOOMCITY_TILE }
        end

        # gray Boom City tiles available in supply, plus how many will be made
        # available by resolving pending upgrades to gray Double Boom City tiles
        def gray_boomcity_tile_potential_count
          gray_boomcity_tile_count +
           [gray_double_boomcity_tile_count, @pending_gray_boom_tile_lays[:double_boom].size].min
        end

        # because gray tiles are limited, their counts could affect pending tile
        # lays, so track them separately
        def pending_boom_tile_lays
          @pending_boom_tile_lays.merge(
            @pending_gray_boom_tile_lays[:boom].map { |h| [h, boomcity_tiles(h.tile.name)] }.to_h
          ).merge(
            @pending_gray_boom_tile_lays[:double_boom].map { |h| [h, [double_boomcity_tile(h.tile.name)]] }.to_h
          )
        end

        # * automatically lay gray Boom upgrades if enough tiles remain
        # * if no such tiles remain, remove the pending gray lays from the list
        #   of pending lays
        # * if some such tiles remain, but not enough for all of the Booming
        #   hexes, then they will be manually resolved by the BoomTrack step
        def handle_gray_booms!
          return if @pending_gray_boom_tile_lays.values.flatten.empty?

          # clear gray double boom city actions, no tiles remain
          if (num_double_boom_tiles = gray_double_boomcity_tile_count).zero?
            @pending_gray_boom_tile_lays[:double_boom].clear

          # there are enough gray double boom city tiles, automatically lay them
          elsif num_double_boom_tiles >= @pending_gray_boom_tile_lays[:double_boom].size
            @pending_gray_boom_tile_lays[:double_boom].each do |hex|
              boomcity_to_double_boomcity!(hex, gray_checked: true)
            end
          end

          # clear pending gray boom city tile lays, no tiles remain
          if gray_boomcity_tile_potential_count.zero?
            @pending_gray_boom_tile_lays[:boom].clear

          # there are enough gray boom city tiles, automatically lay them
          elsif gray_boomcity_tile_count >= @pending_gray_boom_tile_lays[:boom].size
            @pending_gray_boom_tile_lays[:boom].each do |hex|
              boomtown_to_boomcity!(hex, gray_checked: true)
            end
          end
        end

        def postprocess_boom_lay_tile(action)
          hex = action.hex

          if hex.tile.color == :gray
            %i[boom double_boom].each do |kind|
              handle_gray_booms! if @pending_gray_boom_tile_lays[kind].delete(hex)
            end
          end

          @pending_boom_tile_lays.delete(hex)
        end

        def boomcity_tiles(tile_name)
          (BOOMTOWN_TO_BOOMCITY_TILES[tile_name] || []).map { |n| @tiles.find { |t| t.name == n && !t.hex } }.compact
        end

        def double_boomcity_tile(tile_name)
          @tiles.find { |t| t.name == "#{tile_name}B" && !t.hex }
        end

        def all_potential_upgrades(tile, tile_manifest: false, selected_company: nil)
          @pending_boom_tile_lays[tile.hex] || super
        end

        def upgrades_to?(from, to, special = false, selected_company: nil)
          hex = from.hex
          if @pending_boom_tile_lays[hex]
            from.name == to.name.downcase
          else
            return false unless boomer?(from) == boomer?(to)

            if (@development_token_count[hex] >= DTC_DOUBLE_BOOMCITY) &&
               (from.color == :green) && (to.color == :brown)
              return to.name == BROWN_DOUBLE_BOOMCITY_TILE
            end

            if (upgrades = TILE_UPGRADES[from.name])
              upgrades.include?(to.name)
            else
              super
            end
          end
        end

        def revenue_for(route, stops)
          stops.sum do |stop|
            revenue = stop.route_revenue(route.phase, route.train)
            revenue += BOOMING_REVENUE_BONUS if stop.city? && @development_token_count[stop.hex] >= DTC_REVENUE
            revenue
          end
        end

        def active_players
          return super if @pending_boom_tile_lays.empty?

          # when a double Boomtown tile booms, the player who laid it gets to
          # choose which of the two Boomtowns becomes the Boom City
          @pending_boom_tile_lays.keys.map do |hex|
            @tile_layers[hex]
          end.uniq
        end

        def valid_actors(action)
          return super if @pending_boom_tile_lays.empty?

          [@tile_layers[action.hex]]
        end
      end
    end
  end
end
