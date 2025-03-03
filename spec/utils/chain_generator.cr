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
require "file_utils"
require "./transaction"

module ::Units::Utils::ChainGenerator
  include Sushi::Core
  include Sushi::Core::Keys
  include Sushi::Core::Controllers

  def with_factory(developer_fund = nil, &block)
    block_factory = BlockFactory.new(developer_fund)
    yield block_factory, block_factory.transaction_factory
  end

  class MockWebSocket < HTTP::WebSocket
    def initialize
      super(IO::Memory.new)
    end
  end

  class BlockFactory
    @miner : NodeComponents::MinersManager::Miner
    property node_wallet : Wallet
    property miner_wallet : Wallet
    property transaction_factory : TransactionFactory
    property blockchain : Blockchain
    property database : Database
    property node : Sushi::Core::Node

    def initialize(developer_fund)
      test_database = "./test_spec.db"
      @node_wallet = Wallet.from_json(Wallet.create(true).to_json)
      @miner_wallet = Wallet.from_json(Wallet.create(true).to_json)
      FileUtils.rm_rf test_database
      @database = Sushi::Core::Database.new(test_database)
      @node = Sushi::Core::Node.new(true, true, "bind_host", 8008_i32, nil, nil, nil, nil, nil, @node_wallet, @database, developer_fund, false)
      @blockchain = @node.blockchain
      # the node setup is run in a spawn so we have to wait until it's finished before running any tests
      while @node.@phase != Sushi::Core::Node::SetupPhase::DONE
        sleep 0.1
      end
      @miner = {context: {address: miner_wallet.address, nonces: [] of UInt64}, socket: MockWebSocket.new, mid: "535061bddb0549f691c8b9c012a55ee2"}
      @transaction_factory = TransactionFactory.new(@node_wallet)
      @rpc = RPCController.new(@blockchain)
      @rest = RESTController.new(@blockchain)
      FastTransactionPool.clear_all
      SlowTransactionPool.clear_all
      enable_difficulty
    end

    def blocks_to_hold
      @blockchain.blocks_to_hold
    end

    def add_slow_block(with_refresh : Bool = true)
      add_valid_slow_block(with_refresh)
      self
    end

    def add_slow_blocks(number : Int, with_refresh : Bool = true)
      (1..(number * 2)).select(&.even?).each { |_| add_slow_block(with_refresh) }
      self
    end

    def add_slow_block(transactions : Array(Transaction), with_refresh : Bool = true)
      transactions.each { |txn| @blockchain.add_transaction(txn, false) }
      add_valid_slow_block(with_refresh)
      self
    end

    def add_fast_block
      add_valid_fast_block
    end

    def add_fast_blocks(number)
      (1..(number * 2)).select(&.odd?).each { |_| add_fast_block }
      self
    end

    def add_fast_block(transactions : Array(Transaction))
      transactions.each { |txn| @blockchain.add_transaction(txn, false) }
      add_valid_fast_block
      self
    end

    def chain
      remove_difficulty
      @blockchain.chain
    end

    def sub_chain
      @blockchain.chain.reject! { |b| b.prev_hash == "genesis" }
    end

    def remove_difficulty
      ENV.delete("SC_SET_DIFFICULTY")
    end

    def enable_difficulty(difficulty = "0")
      ENV["SC_SET_DIFFICULTY"] = difficulty
    end

    def rpc
      @rpc
    end

    def rest
      @rest
    end

    def miner
      @miner
    end

    private def add_valid_slow_block(with_refresh : Bool)
      enable_difficulty("0")
      @blockchain.refresh_mining_block(0) if with_refresh
      block = @blockchain.mining_block
      block.nonce = 11719215035155661212_u64
      block.difficulty = 0 # difficulty will be set to 0 for most unit tests
      valid_block = @blockchain.valid_block?(block)
      case valid_block
      when SlowBlock
        @blockchain.push_slow_block(valid_block)
      else
        raise "error could not push slow block onto blockchain - block was not valid"
      end
    end

    private def add_valid_fast_block
      valid_transactions = @blockchain.valid_transactions_for_fast_block
      block = @blockchain.mint_fast_block(valid_transactions)
      valid_block = @blockchain.valid_block?(block)
      case valid_block
      when FastBlock
        @blockchain.push_fast_block(valid_block)
      else
        raise "error could not push fast block onto blockchain - block was not valid"
      end
    end
  end

  class TransactionFactory
    include Units::Utils::TransactionHelper

    property recipient_wallet : Wallet
    property sender_wallet : Wallet

    def initialize(sender_wallet : Wallet)
      @sender_wallet = sender_wallet
      @recipient_wallet = Wallet.from_json(Wallet.create(true).to_json)
    end

    def make_send(sender_amount : Int64, token : String = TOKEN_DEFAULT, sender_wallet : Wallet = @sender_wallet, recipient_wallet : Wallet = @recipient_wallet) : Transaction
      transaction_id = Transaction.create_id
      unsigned_transaction = Transaction.new(
        transaction_id,
        "send", # action
        [a_sender(sender_wallet, sender_amount)],
        [a_recipient(recipient_wallet, sender_amount)],
        "0",   # message
        token, # token
        "0",   # prev_hash
        0_i64, # timestamp
        1,     # scaled
        TransactionKind::SLOW
      )
      unsigned_transaction.as_signed([sender_wallet])
    end

    def make_fast_send(sender_amount : Int64, token : String = TOKEN_DEFAULT, sender_wallet : Wallet = @sender_wallet, recipient_wallet : Wallet = @recipient_wallet) : Transaction
      transaction_id = Transaction.create_id
      unsigned_transaction = Transaction.new(
        transaction_id,
        "send", # action
        [a_sender(sender_wallet, sender_amount)],
        [a_recipient(recipient_wallet, sender_amount)],
        "0",   # message
        token, # token
        "0",   # prev_hash
        0_i64, # timestamp
        1,     # scaled
        TransactionKind::FAST
      )
      unsigned_transaction.as_signed([sender_wallet])
    end

    def make_send(sender_amount : Int64, token : String, senders : Array(Transaction::Sender), recipients : Array(Transaction::Recipient), signer_wallets : Array(Wallet), transaction_kind : TransactionKind = TransactionKind::SLOW) : Transaction
      transaction_id = Transaction.create_id
      unsigned_transaction = Transaction.new(
        transaction_id,
        "send", # action
        senders,
        recipients,
        "0",   # message
        token, # token
        "0",   # prev_hash
        0_i64, # timestamp
        1,     # scaled
        transaction_kind
      )
      unsigned_transaction.as_signed(signer_wallets)
    end

    def align_transaction(transaction : Transaction, prev_hash : String) : Transaction
      transaction = transaction.dup
      transaction.prev_hash = prev_hash
      transaction
    end

    def make_send_with_prev_hash(sender_amount : Int64, prev_hash : String, sender_wallet : Wallet = @sender_wallet, recipient_wallet : Wallet = @recipient_wallet) : Transaction
      transaction_id = Transaction.create_id
      unsigned_transaction = Transaction.new(
        transaction_id,
        "send", # action
        [a_sender(sender_wallet, sender_amount)],
        [a_recipient(recipient_wallet, sender_amount)],
        "0",           # message
        TOKEN_DEFAULT, # token
        prev_hash,     # prev_hash
        0_i64,         # timestamp
        1,             # scaled
        TransactionKind::SLOW
      )
      unsigned_transaction.as_signed([sender_wallet])
    end

    def make_buy_domain_from_platform(domain : String, sender_amount : Int64, sender_wallet : Wallet = @sender_wallet) : Transaction
      transaction_id = Transaction.create_id
      unsigned_transaction = Transaction.new(
        transaction_id,
        "scars_buy", # action
        [a_sender(sender_wallet, sender_amount, 20000000_i64)],
        [] of Transaction::Recipient,
        domain,        # message
        TOKEN_DEFAULT, # token
        "0",           # prev_hash
        0_i64,         # timestamp
        1,             # scaled
        TransactionKind::SLOW
      )
      unsigned_transaction.as_signed([sender_wallet])
    end

    def make_buy_domain_from_seller(domain : String, recipient_amount : Int64, recipient_wallet : Wallet = @recipient_wallet) : Transaction
      transaction_id = Transaction.create_id
      unsigned_transaction = Transaction.new(
        transaction_id,
        "scars_buy", # action
        [a_sender(recipient_wallet, recipient_amount, 20000000_i64)],
        [a_recipient(@sender_wallet, 100_i64)],
        domain,        # message
        TOKEN_DEFAULT, # token
        "0",           # prev_hash
        0_i64,         # timestamp
        1,             # scaled
        TransactionKind::SLOW
      )
      unsigned_transaction.as_signed([sender_wallet])
    end

    def make_buy_domain_from_seller(domain : String, recipient_amount : Int64, recipients : Array(Transaction::Recipient)) : Transaction
      transaction_id = Transaction.create_id
      unsigned_transaction = Transaction.new(
        transaction_id,
        "scars_buy", # action
        [a_sender(recipient_wallet, recipient_amount, 20000000_i64)],
        recipients,
        domain,        # message
        TOKEN_DEFAULT, # token
        "0",           # prev_hash
        0_i64,         # timestamp
        1,             # scaled
        TransactionKind::SLOW
      )
      unsigned_transaction.as_signed([sender_wallet])
    end

    def make_sell_domain(domain : String, sender_amount : Int64, sender_wallet : Wallet = @sender_wallet) : Transaction
      transaction_id = Transaction.create_id
      unsigned_transaction = Transaction.new(
        transaction_id,
        "scars_sell", # action
        [a_sender(sender_wallet, sender_amount, 20000000_i64)],
        [a_recipient(sender_wallet, sender_amount)],
        domain,        # message
        TOKEN_DEFAULT, # token
        "0",           # prev_hash
        0_i64,         # timestamp
        1,             # scaled
        TransactionKind::SLOW
      )
      unsigned_transaction.as_signed([sender_wallet])
    end

    def make_sell_domain(domain : String, sender_amount : Int64, recipients : Array(Transaction::Recipient), sender_wallet : Wallet = @sender_wallet) : Transaction
      transaction_id = Transaction.create_id
      unsigned_transaction = Transaction.new(
        transaction_id,
        "scars_sell", # action
        [a_sender(sender_wallet, sender_amount, 20000000_i64)],
        recipients,
        domain,        # message
        TOKEN_DEFAULT, # token
        "0",           # prev_hash
        0_i64,         # timestamp
        1,             # scaled
        TransactionKind::SLOW
      )
      unsigned_transaction.as_signed([sender_wallet])
    end

    def make_cancel_domain(domain : String, sender_amount : Int64, sender_wallet : Wallet = @sender_wallet) : Transaction
      transaction_id = Transaction.create_id
      unsigned_transaction = Transaction.new(
        transaction_id,
        "scars_cancel", # action
        [a_sender(sender_wallet, sender_amount, 20000000_i64)],
        [a_recipient(sender_wallet, sender_amount)],
        domain,        # message
        TOKEN_DEFAULT, # token
        "0",           # prev_hash
        0_i64,         # timestamp
        1,             # scaled
        TransactionKind::SLOW
      )
      unsigned_transaction.as_signed([sender_wallet])
    end

    def make_cancel_domain(domain : String, sender_amount : Int64, recipients : Array(Transaction::Recipient), sender_wallet : Wallet = @sender_wallet) : Transaction
      transaction_id = Transaction.create_id
      unsigned_transaction = Transaction.new(
        transaction_id,
        "scars_cancel", # action
        [a_sender(sender_wallet, sender_amount, 20000000_i64)],
        recipients,
        domain,        # message
        TOKEN_DEFAULT, # token
        "0",           # prev_hash
        0_i64,         # timestamp
        1,             # scaled
        TransactionKind::SLOW
      )
      unsigned_transaction.as_signed([sender_wallet])
    end

    def make_create_token(token : String, sender_amount : Int64, sender_wallet : Wallet = @sender_wallet, recipient_wallet : Wallet = @recipient_wallet) : Transaction
      transaction_id = Transaction.create_id
      unsigned_transaction = Transaction.new(
        transaction_id,
        "create_token", # action
        [a_sender(sender_wallet, sender_amount, 20000000_i64)],
        [a_recipient(sender_wallet, sender_amount)],
        "0",   # message
        token, # token
        "0",   # prev_hash
        0_i64, # timestamp
        1,     # scaled
        TransactionKind::SLOW
      )
      unsigned_transaction.as_signed([sender_wallet])
    end

    def make_create_token(token : String, senders : Array(Transaction::Sender), recipients : Array(Transaction::Recipient), sender_wallet : Wallet, transaction_kind : TransactionKind = TransactionKind::SLOW) : Transaction
      transaction_id = Transaction.create_id
      unsigned_transaction = Transaction.new(
        transaction_id,
        "create_token", # action
        senders,
        recipients,
        "0",   # message
        token, # token
        "0",   # prev_hash
        0_i64, # timestamp
        1,     # scaled
        transaction_kind
      )
      unsigned_transaction.as_signed([sender_wallet])
    end
  end
end
