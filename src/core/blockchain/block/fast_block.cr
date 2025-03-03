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

module ::Sushi::Core
  class FastBlock
    extend Hashes

    JSON.mapping({
      index:            Int64,
      transactions:     Array(Transaction),
      prev_hash:        String,
      merkle_tree_root: String,
      timestamp:        Int64,
      kind:             BlockKind,
      address:          String,
      public_key:       String,
      sign_r:           String,
      sign_s:           String,
      hash:             String,
    })

    def initialize(
      @index : Int64,
      @transactions : Array(Transaction),
      @prev_hash : String,
      @timestamp : Int64,
      @address : String,
      @public_key : String,
      @sign_r : String,
      @sign_s : String,
      @hash : String
    )
      raise "index must be odd number" if index.even?
      @merkle_tree_root = calculate_merkle_tree_root
      @kind = BlockKind::FAST
    end

    def to_header : Blockchain::FastHeader
      {
        index:            @index,
        prev_hash:        @prev_hash,
        merkle_tree_root: @merkle_tree_root,
        timestamp:        @timestamp,
      }
    end

    def to_hash : String
      string = FastBlockNoTimestamp.from_fast_block(self).to_json
      sha256(string)
    end

    def calculate_merkle_tree_root : String
      return "" if @transactions.size == 0

      current_hashes = @transactions.map { |tx| tx.to_hash }

      loop do
        tmp_hashes = [] of String

        (current_hashes.size / 2).times do |i|
          tmp_hashes.push(sha256(current_hashes[i*2] + current_hashes[i*2 + 1]))
        end

        tmp_hashes.push(current_hashes[-1]) if current_hashes.size % 2 == 1

        current_hashes = tmp_hashes
        break if current_hashes.size == 1
      end

      ripemd160(current_hashes[0])
    end

    def valid?(blockchain : Blockchain, skip_transactions : Bool = false) : Bool
      return valid_as_latest?(blockchain, skip_transactions) unless @index == 0
      valid_as_genesis?
    end

    def is_slow_block?
      @kind == BlockKind::SLOW
    end

    def is_fast_block?
      @kind == BlockKind::FAST
    end

    def kind : String
      is_fast_block? ? "FAST" : "SLOW"
    end

    def valid?(blockchain : Blockchain, skip_transactions : Bool = false) : Bool
      return valid_as_latest?(blockchain, skip_transactions) unless @index == 0
      valid_as_genesis?
    end

    private def process_transaction(blockchain, transaction, idx)
      t = FastTransactionPool.find(transaction) || transaction
      t.valid_common?

      if idx == 0
        t.valid_as_coinbase?(blockchain, @index, transactions[1..-1])
      else
        t.valid_as_embedded?(blockchain, transactions[0..idx - 1])
      end
    end

    def valid_as_latest?(blockchain : Blockchain, skip_transactions : Bool) : Bool
      valid_signature = ECCrypto.verify(
        @public_key,
        @hash,
        @sign_r,
        @sign_s
      )
      raise "Invalid Block Signature: the current block index: #{@index} has an invalid signature" unless valid_signature

      valid_leader = Ranking.rank(@address, Ranking.chain(blockchain.chain)) > 0
      raise "Invalid leader: the block was signed by a leader who is not ranked" unless valid_leader

      prev_block = blockchain.latest_fast_block || blockchain.get_genesis_block
      latest_fast_index = blockchain.get_latest_index_for_fast

      unless skip_transactions
        transactions.each_with_index do |t, idx|
          process_transaction(blockchain, t, idx)
        end
      end

      if latest_fast_index > 1
        raise "Index Mismatch: the current block index: #{@index} should match the lastest fast block index: #{latest_fast_index}" if @index != latest_fast_index
        raise "Invalid Previous Hash: for current index: #{@index} the prev_hash is invalid: (prev index: #{prev_block.index}) #{prev_block.to_hash} != #{@prev_hash}" if prev_block.to_hash != @prev_hash
      end

      next_timestamp = __timestamp
      prev_timestamp = prev_block.timestamp

      if prev_timestamp > @timestamp || next_timestamp < @timestamp
        raise "Invalid Timestamp: #{@timestamp} " +
              "(timestamp should be bigger than #{prev_timestamp} and smaller than #{next_timestamp})"
      end

      merkle_tree_root = calculate_merkle_tree_root

      if merkle_tree_root != @merkle_tree_root
        raise "Invalid Merkle Tree Root: (expected #{@merkle_tree_root} but got #{merkle_tree_root})"
      end

      true
    end

    def valid_as_genesis? : Bool
      false
    end

    def find_transaction(transaction_id : String) : Transaction?
      @transactions.find { |t| t.id == transaction_id }
    end

    def set_transactions(txns : Transactions)
      @transactions = txns
      verbose "Number of transactions in block: #{txns.size}"
      @merkle_tree_root = calculate_merkle_tree_root
    end

    include Block
    include Hashes
    include Logger
    include Protocol
    include Consensus
    include Common::Timestamp
  end

  class FastBlockNoTimestamp
    JSON.mapping({
      index:            Int64,
      transactions:     Array(Transaction),
      prev_hash:        String,
      merkle_tree_root: String,
      address:          String,
      public_key:       String,
      sign_r:           String,
      sign_s:           String,
      hash:             String,
    })

    def self.from_fast_block(b : FastBlock)
      self.new(b.index, b.transactions, b.prev_hash, b.merkle_tree_root, b.address, b.public_key, b.sign_r, b.sign_s, b.hash)
    end

    def initialize(
      @index : Int64,
      @transactions : Array(Transaction),
      @prev_hash : String,
      @merkle_tree_root : String,
      @address : String,
      @public_key : String,
      @sign_r : String,
      @sign_s : String,
      @hash : String
    )
    end
  end
end
