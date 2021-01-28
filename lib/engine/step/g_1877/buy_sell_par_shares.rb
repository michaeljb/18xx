# frozen_string_literal: true

require_relative '../g_1817/buy_sell_par_shares'

module Engine
  module Step
    module G1877
      class BuySellParShares < Step::G1817::BuySellParShares
        def corporate_actions(entity)
          actions = super
          actions << 'buy_train' if can_buy_train?(entity)
          actions
        end

        def room?(entity, _shell = nil)
          entity.trains.size < @game.phase.train_limit(entity)
        end

        def can_buy_train?(entity)
          return false unless entity.corporation?
          return false if entity.operated?
          return false unless entity.owned_by?(current_entity)

          room?(entity) && entity.cash >= @depot.min_price(entity)
        end

        def buyable_train_variants(train, entity)
          train.variants.values.select { |v| v[:price] <= entity.cash }
        end

        def buyable_trains(corporation)
          @depot.depot_trains.select { |train| train.price <= corporation.cash }
        end

        def must_buy_train?(_entity)
          false
        end

        def should_buy_train?(entity); end

        def issuable_shares(_entity)
          []
        end

        def president_may_contribute?(_entity, _shell = nil)
          false
        end

        def win_bid(winner, _company)
          @winning_bid = winner
          entity = @winning_bid.entity
          corporation = @winning_bid.corporation
          price = @winning_bid.price

          @log << "#{entity.name} wins bid on #{corporation.name} for #{@game.format_currency(price)}"

          share_price = @game.find_share_price(price / 2)

          action = Action::Par.new(entity, corporation: corporation, share_price: share_price)
          process_par(action)

          @corporation_size = nil
          size_corporation(@game.phase.corporation_sizes.first) if @game.phase.corporation_sizes.one?

          @game.share_pool.transfer_shares(ShareBundle.new(corporation.shares), @game.share_pool)

          par_corporation if available_subsidiaries(winner.entity).none?
        end

        def can_short?(entity, corporation)
          shorts = @game.shorts(corporation).size

          corporation.floated? &&
            shorts < corporation.total_shares &&
            entity.num_shares_of(corporation) <= 0 &&
            !(corporation.share_price.acquisition? || corporation.share_price.liquidation?) &&
            !@round.players_sold[entity].values.include?(:short)
        end

        def process_buy_train(action)
          if @corporate_action && action.entity != @corporate_action.entity
            raise GameError, 'Cannot act as multiple corporations'
          end

          @corporate_action = action
          @round.last_to_act = action.entity.player

          entity ||= action.entity
          train = action.train
          price = action.price

          raise GameError, 'Not a buyable train' unless buyable_train_variants(train, entity).include?(train.variant)
          raise GameError, 'Must pay face value' if price != train.price

          @game.queue_log! { @game.phase.buying_train!(entity, train) }

          source = @depot.discarded.include?(train) ? 'The Discard' : train.owner.name

          @log << "#{entity.name} buys a #{train.name} train for "\
            "#{@game.format_currency(price)} from #{source}"

          @game.flush_log!

          @game.buy_train(entity, train, price)
        end

        def setup
          super

          @depot = @game.depot
        end
      end
    end
  end
end
