# Copyright © 2017-2018 The SushiChain Core developers
#
# See the LICENSE file at the top-level directory of this distribution
# for licensing information.
#
# Unless otherwise agreed in a custom licensing agreement with the SushiChain Core developers,
# no part of this software, including this file, may be copied, modified,
# propagated, or distributed except according to the terms contained in the
# LICENSE file.
#
# Removal or modification of this copyright notice is prohibited.

require "spinach"
require "./../spec_helper"

class Transactions < SpinachTestCase
  include Units::Utils

  @[Spinach]
  def send_amount(args)
    amount = args.first
    fee_amount = args.last

    wallet_a = Wallet.from_json(Wallet.create(true).to_json)
    wallet_b = Wallet.from_json(Wallet.create(true).to_json)

    wallet_a_amount = Quantity.as_fund_amount("wallet_balance_a", @variables)
    wallet_b_amount = Quantity.as_fund_amount("wallet_balance_b", @variables)
    developer_fund = DeveloperFunds.with_funds([
      {"address" => wallet_a.address, "amount" => wallet_a_amount},
      {"address" => wallet_b.address, "amount" => wallet_b_amount},
      ])

    with_factory(developer_fund) do |block_factory, transaction_factory|
      transaction = send_token_transaction(transaction_factory, "SUSHI", amount, fee_amount, wallet_a, wallet_b)
      block_factory.add_slow_block([transaction])

      wallet_a_final_balance = Wallets.balance_for(wallet_a, block_factory)
      wallet_b_final_balance = Wallets.balance_for(wallet_b, block_factory)

      rejected = block_factory.blockchain.rejects.@rejects.keys.size.to_s

      {"wallet_balance_a" => wallet_a_final_balance, "wallet_balance_b" => wallet_b_final_balance, "rejections" => rejected}
    end
  end

  @[Spinach]
  def create_token(args)
    token_name = args.first
    token_amount = args[1]
    fee_amount = args.last

    wallet_a = Wallet.from_json(Wallet.create(true).to_json)
    wallet_a_amount = Quantity.as_fund_amount("wallet_balance_a", @variables)
    developer_fund = DeveloperFunds.with_funds([
      {"address" => wallet_a.address, "amount" => wallet_a_amount}
      ])

    with_factory(developer_fund) do |block_factory, transaction_factory|

      transaction = create_custom_token_transaction(transaction_factory, token_name, token_amount, fee_amount, wallet_a)
      block_factory.add_slow_block([transaction])

      wallet_a_final_balance = Wallets.balance_for(wallet_a, block_factory)
      wallet_a_final_custom_balance = Wallets.balance_for(wallet_a, block_factory, token_name)

      rejected = block_factory.blockchain.rejects.@rejects.keys.size.to_s
      pp block_factory.blockchain.rejects.@rejects.values

      {"wallet_balance_a" => wallet_a_final_balance, "wallet_balance_a_custom" => wallet_a_final_custom_balance, "rejections" => rejected}
    end
  end

  @[Spinach]
  def send_custom_token(args)
    token_name = args.first
    amount = args[1]
    fee_amount = args.last

    wallet_a = Wallet.from_json(Wallet.create(true).to_json)
    wallet_b = Wallet.from_json(Wallet.create(true).to_json)

    wallet_a_amount = Quantity.as_fund_amount("wallet_balance_a_sushi", @variables)
    wallet_b_amount = Quantity.as_fund_amount("wallet_balance_b_sushi", @variables)
    developer_fund = DeveloperFunds.with_funds([
      {"address" => wallet_a.address, "amount" => wallet_a_amount},
      {"address" => wallet_b.address, "amount" => wallet_b_amount},
      ])

    with_factory(developer_fund) do |block_factory, transaction_factory|

      wallet_balance_a_kings = Quantity.as_fund_amount("wallet_balance_a_kings", @variables)
      kings_create_transaction = create_custom_token_transaction(transaction_factory, token_name, wallet_balance_a_kings, "0.1", wallet_a)
      kings_send_transaction = send_token_transaction(transaction_factory, token_name, amount, fee_amount, wallet_a, wallet_b)
      block_factory.add_slow_block([kings_create_transaction]).add_slow_block([kings_send_transaction])

      wallet_a_final_balance = Wallets.balance_for(wallet_a, block_factory)
      wallet_b_final_balance = Wallets.balance_for(wallet_b, block_factory)

      wallet_balance_a_kings = Wallets.balance_for(wallet_a, block_factory, token_name)
      wallet_balance_b_kings = Wallets.balance_for(wallet_b, block_factory, token_name)

      rejected = block_factory.blockchain.rejects.@rejects.keys.size.to_s

      pp block_factory.blockchain.rejects.@rejects.values

      {"wallet_balance_a" => wallet_a_final_balance, "wallet_balance_b" => wallet_b_final_balance, "wallet_balance_a_kings" => wallet_balance_a_kings, "wallet_balance_b_kings" => wallet_balance_b_kings, "rejections" => rejected}
    end


  end

  private def send_token_transaction(transaction_factory, token_name, amount, fee_amount, wallet_a, wallet_b)
    amount_to_send = Quantity.as_internal_amount(amount)
    fee = Quantity.as_internal_amount(fee_amount)
    senders = Transactions.single_sender(wallet_a, amount_to_send, fee)
    recipients = Transactions.single_recipient(wallet_b, amount_to_send)
    transaction_factory.make_send(amount_to_send, token_name, senders, recipients, [wallet_a])
  end

  private def create_custom_token_transaction(transaction_factory, token_name, token_amount, fee_amount, wallet)
    amount_to_create = Quantity.as_internal_amount(token_amount)
    fee = Quantity.as_internal_amount(fee_amount)
    senders = Transactions.single_sender(wallet, amount_to_create, fee)
    recipients = Transactions.single_recipient(wallet, amount_to_create)
    transaction_factory.make_create_token(token_name, senders, recipients, wallet)
  end
end
