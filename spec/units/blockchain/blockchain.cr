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

require "./../../spec_helper"
require "benchmark"

include Sushi::Core
include Hashes
include Units::Utils
include Sushi::Core::DApps::BuildIn
include Sushi::Core::Controllers
include Sushi::Core::Block

describe Blockchain do
  describe "setup" do
    it "should create a genesis block" do
      with_factory do |block_factory|
        block = block_factory.chain.first
        block.kind.should eq("SLOW")
        block.prev_hash.should eq("genesis")
      end
    end
  end

  describe "mining_block_difficulty_miner" do
    it "should return the miner difficulty" do
      with_factory do |block_factory|
        block_factory.blockchain.mining_block_difficulty_miner.should eq(0)
      end
    end
  end

  describe "mining_block_difficulty" do
    it "should return the chian difficulty" do
      with_factory do |block_factory|
        block_factory.blockchain.mining_block_difficulty.should eq(0)
      end
    end
  end

  describe "replace_chain" do
    it "should return false if no subchains and do nothing" do
      with_factory do |block_factory|
        before = block_factory.chain
        block_factory.blockchain.replace_chain(nil, nil).should eq(false)
        before.should eq(block_factory.chain)
      end
    end

    it "should return true and replace slow chain" do
      with_factory do |block_factory|
        slow_sub_chain = block_factory.add_slow_blocks(10).chain
        test_database = "./test_spec2.db"
        FileUtils.rm_rf test_database
        database = Sushi::Core::Database.new(test_database)
        blockchain = Blockchain.new(block_factory.node_wallet, database, nil)
        blockchain.setup(block_factory.node)

        expected = (blockchain.chain + slow_sub_chain[1..-1]).map(&.index).sort

        blockchain.replace_chain(slow_sub_chain[1..-1], nil).should eq(true)
        blockchain.chain.map(&.index).sort.should eq(expected)
      end
    end

    it "should return true and replace fast chain" do
      with_factory do |block_factory|
        chain = block_factory.add_slow_blocks(2).add_fast_blocks(10).chain
        fast_sub_chain = chain.select(&.is_fast_block?)
        slow_block_1 = chain[2].as(SlowBlock)
        slow_block_2 = chain[4].as(SlowBlock)

        test_database = "./test_spec2.db"
        FileUtils.rm_rf test_database
        database = Sushi::Core::Database.new(test_database)
        blockchain = Blockchain.new(block_factory.node_wallet, database, nil)
        blockchain.setup(block_factory.node)
        blockchain.push_slow_block(slow_block_1)
        blockchain.push_slow_block(slow_block_2)

        expected = ([blockchain.chain.first, slow_block_1, slow_block_2] + fast_sub_chain[0..-1]).map(&.index).sort
        blockchain.replace_chain(nil, fast_sub_chain[0..-1]).should eq(true)
        blockchain.chain.map(&.index).sort.should eq(expected)
      end
    end

    it "should return true and replace fast and slow chain" do
      with_factory do |block_factory|
        chain = block_factory.add_slow_blocks(6).add_fast_blocks(10).chain
        fast_sub_chain = chain.select(&.is_fast_block?)
        slow_block_1 = chain[2].as(SlowBlock)
        slow_sub_chain = chain.select(&.is_slow_block?)

        test_database = "./test_spec2.db"
        FileUtils.rm_rf test_database
        database = Sushi::Core::Database.new(test_database)
        blockchain = Blockchain.new(block_factory.node_wallet, database, nil)
        blockchain.setup(block_factory.node)
        blockchain.push_slow_block(slow_block_1)
        expected = (blockchain.chain + slow_sub_chain[2..-1] + fast_sub_chain[0..-1]).map(&.index).sort
        blockchain.replace_chain(slow_sub_chain[2..-1], fast_sub_chain[0..-1]).should eq(true)
        blockchain.chain.map(&.index).sort.should eq(expected)
      end
    end
  end

  describe "add_transaction" do
    it "should add a transaction to the pool" do
      with_factory do |block_factory, transaction_factory|
        transaction = transaction_factory.make_send(200000000_i64)
        blockchain = block_factory.blockchain
        blockchain.add_transaction(transaction, false)
        blockchain.pending_slow_transactions.first.should eq(transaction)
        blockchain.embedded_slow_transactions.first.should eq(transaction)
      end
    end

    it "should reject a transaction if invalid" do
      with_factory do |block_factory, transaction_factory|
        transaction = transaction_factory.make_send(-200000000_i64)
        blockchain = block_factory.blockchain
        blockchain.add_transaction(transaction, false)
        blockchain.pending_slow_transactions.size.should eq(0)
        blockchain.embedded_slow_transactions.size.should eq(0)
        blockchain.rejects.find(transaction.id).should eq("the amount is out of range")
      end
    end

    it "should reject a transaction if already present" do
      with_factory do |block_factory, transaction_factory|
        transaction = transaction_factory.make_send(200000000_i64)
        block_factory.add_slow_block([transaction]).add_slow_blocks(3)
        blockchain = block_factory.blockchain
        blockchain.add_transaction(transaction, false)
        blockchain.add_transaction(transaction, false)
        block_factory.add_slow_blocks(2)
        blockchain.pending_slow_transactions.size.should eq(0)
        blockchain.embedded_slow_transactions.size.should eq(0)
        blockchain.rejects.find(transaction.id).should eq("the transaction #{transaction.id} is already included in 2")
      end
    end
  end

  describe "latest_block" do
    it "should return the latest block when slow" do
      with_factory do |block_factory|
        block_factory.add_slow_blocks(3)
        blockchain = block_factory.blockchain
        blockchain.latest_block.index.should eq(6)
      end
    end

    it "should return the latest block when fast" do
      with_factory do |block_factory|
        block_factory.add_slow_blocks(3).add_fast_blocks(4)
        blockchain = block_factory.blockchain
        blockchain.latest_block.index.should eq(7)
      end
    end
  end

  describe "latest_slow_block" do
    it "should return the latest slow block" do
      with_factory do |block_factory|
        block_factory.add_slow_blocks(3).add_fast_blocks(2)
        blockchain = block_factory.blockchain
        blockchain.latest_block.index.should eq(6)
      end
    end
  end

  describe "latest_index" do
    it "should return the latest index when slow" do
      with_factory do |block_factory|
        block_factory.add_slow_blocks(3)
        blockchain = block_factory.blockchain
        blockchain.latest_index.should eq(6)
      end
    end

    it "should return the latest index when fast" do
      with_factory do |block_factory|
        block_factory.add_slow_blocks(3).add_fast_blocks(4)
        blockchain = block_factory.blockchain
        blockchain.latest_index.should eq(7)
      end
    end
  end

  describe "get_latest_index_for_slow" do
    it "should return the latest index when slow" do
      with_factory do |block_factory|
        block_factory.add_slow_blocks(3).add_fast_blocks(4)
        blockchain = block_factory.blockchain
        blockchain.get_latest_index_for_slow.should eq(8)
      end
    end
  end

  describe "subchain_slow" do
    it "should return the slow subchain" do
      with_factory do |block_factory|
        block_factory.add_slow_blocks(3).add_fast_blocks(4)
        blockchain = block_factory.blockchain
        indexes = blockchain.subchain_slow(0).not_nil!.map(&.index)
        indexes.should eq([2, 4, 6])
      end
    end

    it "should return the slow subchain with index at the middle of the chain" do
      with_factory do |block_factory|
        block_factory.add_slow_blocks(6).add_fast_blocks(4)
        blockchain = block_factory.blockchain
        indexes = blockchain.subchain_slow(4).not_nil!.map(&.index)
        indexes.should eq([6, 8, 10, 12])
      end
    end
  end

  describe "restore from database" do
    it "should load the whole chain from the database when the chain size is less than the memory allocation" do
      with_factory do |block_factory|
        block_factory.add_slow_blocks(10)
        test_database = "./test_spec.db"
        database = Sushi::Core::Database.new(test_database)
        blockchain = Blockchain.new(block_factory.node_wallet, database, nil)
        blockchain.setup(block_factory.node)
        # including genesis block total chain size should be 11
        blockchain.chain.size.should eq(11)
      end
    end
    it "should load a subset of the whole chain from the database when the chain size is more than the memory allocation" do
      with_factory do |block_factory|
        blocks_to_add = block_factory.blocks_to_hold + 8
        block_factory.add_slow_blocks(blocks_to_add)
        test_database = "./test_spec.db"
        database = Sushi::Core::Database.new(test_database)
        blockchain = Blockchain.new(block_factory.node_wallet, database, nil)
        blockchain.setup(block_factory.node)
        # including genesis block total chain size should be the number of blocks to hold + 1
        blockchain.chain.size.should eq(blockchain.blocks_to_hold + 1)
      end
    end
  end

  describe "in memory syncing" do
    describe "slow chain" do
      # TODO - remove this test when the syncing is all fixed as it's covered indirectly by another spec here
      it "should return the whole slow chain as a subchain when the chain size is less than the in memory allocation" do
        with_factory do |block_factory|
          block_factory.add_slow_blocks(10)
          blockchain = block_factory.blockchain
          indexes = blockchain.subchain_slow(0).not_nil!.map(&.index)
          indexes.first.should eq(2)
          indexes.last.should eq(20)
        end
      end
      # TODO - Fix this spec
      # TODO - remove this test when the syncing is all fixed as it's super slow
      it "should return the whole slow chain as a subchain when the chain size exceeds the in memory allocation" do
        with_factory do |block_factory|
          blocks_to_add = block_factory.blocks_to_hold + 8
          block_factory.add_slow_blocks(blocks_to_add)
          blockchain = block_factory.blockchain
          indexes = blockchain.subchain_slow(0).not_nil!.map(&.index)
          indexes.first.should eq(2)
          indexes.last.should eq((blockchain.blocks_to_hold * 2) + (8 * 2))
        end
      end
    end
    describe "fast chain" do
      # TODO - remove this test when the syncing is all fixed as it's covered indirectly by another spec here
      it "should return the whole fast chain as a subchain when the fast chain size is less than the in memory allocation" do
        with_factory do |block_factory|
          block_factory.add_slow_blocks(1).add_fast_blocks(4)
          blockchain = block_factory.blockchain
          indexes = blockchain.subchain_fast(0).not_nil!.map(&.index)
          indexes.first.should eq(1)
          indexes.last.should eq(7)
        end
      end
      # TODO - remove this test when the syncing is all fixed as it's super slow
      it "should return the whole fast chain as a subchain when the fast chain size exceeds the in memory allocation" do
        with_factory do |block_factory|
          blocks_to_add = block_factory.blocks_to_hold + 8
          block_factory.add_slow_blocks(1).add_fast_blocks(blocks_to_add)
          blockchain = block_factory.blockchain
          indexes = blockchain.subchain_fast(0).not_nil!.map(&.index)
          indexes.first.should eq(1)
          indexes.last.should eq((blockchain.blocks_to_hold * 2) + (8 * 2) - 1)
        end
      end
    end
  end

  describe "headers" do
    it "should return the headers" do
      with_factory do |block_factory|
        block_factory.add_slow_blocks(3).add_fast_blocks(4)
        blockchain = block_factory.blockchain
        header_indexes = blockchain.headers.map(&.["index"])
        header_indexes.should eq([0, 1, 2, 3, 4, 5, 6, 7])
      end
    end
  end

  describe "transactions_for_address" do
    it "should return all transactions for address" do
      with_factory do |block_factory, transaction_factory|
        block_factory.add_slow_blocks(3).add_fast_blocks(4).add_slow_block([transaction_factory.make_send(200000000_i64)])
        blockchain = block_factory.blockchain
        all = blockchain.transactions_for_address(block_factory.node_wallet.address)
        all.size.should eq(5)
      end
    end

    it "should return 'send' transactions for address" do
      with_factory do |block_factory, transaction_factory|
        block_factory.add_slow_blocks(3).add_fast_blocks(4).add_slow_block([transaction_factory.make_send(200000000_i64)])
        blockchain = block_factory.blockchain
        all = blockchain.transactions_for_address(block_factory.node_wallet.address, 0, 20, ["send"])
        all.size.should eq(1)
      end
    end

    it "should return paginated transactions for address" do
      with_factory do |block_factory, transaction_factory|
        block_factory.add_slow_blocks(5).add_fast_blocks(5).add_slow_block([transaction_factory.make_send(200000000_i64)])
        blockchain = block_factory.blockchain
        blockchain.transactions_for_address(block_factory.node_wallet.address, 0, 3).size.should eq(3)
        blockchain.transactions_for_address(block_factory.node_wallet.address, 2, 1).size.should eq(1)
      end
    end
  end

  describe "available_actions" do
    it "should return 'send' transactions for address" do
      with_factory do |block_factory, transaction_factory|
        block_factory.add_slow_blocks(3).add_fast_blocks(4).add_slow_block([transaction_factory.make_send(200000000_i64)])
        blockchain = block_factory.blockchain
        blockchain.available_actions.should eq(["send", "scars_buy", "scars_sell", "scars_cancel", "create_token"])
      end
    end
  end

  describe "refresh_slow_pending_block" do
    it "should refresh the pending block" do
      with_factory do |block_factory, transaction_factory|
        blockchain = block_factory.blockchain
        blockchain.mining_block.index.should eq(2)
        block_factory.add_slow_blocks(2, false).add_slow_block([transaction_factory.make_send(200000000_i64)], false)
        blockchain.refresh_mining_block(8)
        blockchain.mining_block.index.should eq(8)
      end
    end
  end

  describe "align_slow_transactions" do
    it "should align the slow transactions" do
      with_factory do |block_factory, transaction_factory|
        blockchain = block_factory.blockchain
        block_factory.add_slow_blocks(2, false).add_fast_blocks(4).add_slow_block([transaction_factory.make_send(200000000_i64)], false)
        blockchain.refresh_mining_block(8)
        coinbase_transaction = block_factory.chain.last.transactions.first
        blockchain.align_slow_transactions(coinbase_transaction, 1).size.should eq(2)
      end
    end
  end

  describe "create_coinbase_slow_transaction" do
    it "should create a slow coinbase transaction" do
      with_factory do |block_factory, transaction_factory|
        blockchain = block_factory.blockchain
        block_factory.add_slow_blocks(2).add_fast_blocks(4).add_slow_block([transaction_factory.make_send(200000000_i64)])
        amount = 200000000_i64
        transaction = blockchain.create_coinbase_slow_transaction(amount, [block_factory.miner])
        transaction.action.should eq("head")
        recipient = transaction.recipients.first
        recipient[:address].should eq(block_factory.node_wallet.address)
        recipient[:amount].should eq(amount)
      end
    end
  end

  describe "coinbase_slow_amount" do
    it "should calculate the reward excluding fees (transactions are not taken into account)" do
      with_factory do |block_factory, transaction_factory|
        blockchain = block_factory.blockchain
        amount = 200000000_i64
        block_factory.add_slow_blocks(2)
          .add_fast_blocks(4)
          .add_slow_block([transaction_factory.make_send(amount), transaction_factory.make_send(amount)])
        transactions = blockchain.embedded_slow_transactions
        blockchain.coinbase_slow_amount(0, transactions).should eq(1200000000)
      end
    end

    it "should calculate the reward based on fees (no more minable blocks so all rewards come from fees)" do
      with_factory do |block_factory, transaction_factory|
        blockchain = block_factory.blockchain
        amount = 200000000_i64
        block_factory.add_slow_blocks(2, false)
          .add_fast_blocks(4)
          .add_slow_block([transaction_factory.make_send(amount), transaction_factory.make_send(amount)], false)
        transactions = blockchain.embedded_slow_transactions
        blockchain.coinbase_slow_amount(blockchain.@block_reward_calculator.max_blocks + 1, transactions).should eq(20000)
      end
    end
  end

  describe "total_fees" do
    it "should calculate the total fees based on the transactions" do
      with_factory do |block_factory, transaction_factory|
        blockchain = block_factory.blockchain
        amount = 200000000_i64
        block_factory.add_slow_blocks(2, false)
          .add_fast_blocks(4)
          .add_slow_block([transaction_factory.make_send(amount), transaction_factory.make_send(amount)], false)
        transactions = blockchain.embedded_slow_transactions
        blockchain.total_fees(transactions).should eq(20000)
      end
    end
  end

  describe "replace_slow_transactions" do
    it "should validate and add new transactions that have arrived" do
      with_factory do |block_factory, transaction_factory|
        transaction1 = transaction_factory.make_send(200000000_i64)
        transaction2 = transaction_factory.make_send(300000000_i64)
        blockchain = block_factory.blockchain
        blockchain.pending_slow_transactions.size.should eq(0)
        blockchain.replace_slow_transactions([transaction1, transaction2])
        blockchain.pending_slow_transactions.size.should eq(2)
      end
    end

    it "should reject any invalid transactions" do
      with_factory do |block_factory, transaction_factory|
        transaction1 = transaction_factory.make_send(200000000_i64)
        transaction2 = transaction_factory.make_send(-300000000_i64)
        blockchain = block_factory.blockchain
        blockchain.pending_slow_transactions.size.should eq(0)
        blockchain.replace_slow_transactions([transaction1, transaction2])
        blockchain.pending_slow_transactions.size.should eq(1)
        blockchain.rejects.find(transaction2.id).should eq("the amount is out of range")
      end
    end
  end

  it "align transactions" do
    with_factory do |block_factory, transaction_factory|
      transaction_total = 10
      transactions = (1..transaction_total).to_a.map { |n| transaction_factory.make_send(n.to_i64) }

      block_factory.add_slow_block(transactions, false)
      block_factory.blockchain.embedded_slow_transactions.size.should eq(transaction_total)
      coinbase_transaction = block_factory.blockchain.chain.last.transactions.first

      puts Benchmark.measure {
        block_factory.blockchain.align_slow_transactions(coinbase_transaction, 1)
      }
    end
  end

  it "clean transactions" do
    with_factory do |block_factory, transaction_factory|
      transaction_total = 10
      transactions = (1..transaction_total).to_a.map { |n| transaction_factory.make_send(n.to_i64) }

      block_factory.add_slow_block(transactions, false)
      block_factory.blockchain.pending_slow_transactions.size.should eq(transaction_total)

      puts Benchmark.measure {
        block_factory.blockchain.clean_slow_transactions
      }
    end
  end

  STDERR.puts "< Blockchain::Slow"
end
