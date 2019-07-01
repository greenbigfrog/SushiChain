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

module ::Sushi::Core::Consensus

  def valid_pow?(block_hash : String, nonce : UInt64, difficulty : Int32, debug_pow = false) : Bool
    nonce_salt = nonce.to_s(16)
    nonce_salt = "0" + nonce_salt if nonce_salt.bytesize % 2 != 0

    nonce_slice = Slice(UInt8).new(nonce_salt.bytesize / 2)
    nonce_slice.size.times do |i|
      nonce_slice[i] = nonce_salt[i*2..i*2 + 1].to_u8(16)
    end

    buffer = Argon2::Engine.raw_hash_buffer(
      #jjf Argon2::Engine::EngineType::ARGON2ID, block_hash, nonce_slice.hexstring, 1, 8, 512)
      Argon2::Engine::EngineType::ARGON2ID, block_hash, nonce_slice.hexstring, 1, 16, 512)

    bits = buffer.flat_map { |b| (0..7).map { |n| b.bit(n) }.reverse }

    if debug_pow
      leading_bits = bits[0, difficulty].join("")
      debug "Leading bits: #{leading_bits} indicates difficulty of #{leading_bits.size}"
    end

    bits[0, difficulty].join("") == "0" * difficulty
  end

  def valid_nonce?(block_hash : String, nonce : UInt64, difficulty : Int32) : Bool
    difficulty = ENV["SC_SET_DIFFICULTY"].to_i if ENV.has_key?("SC_SET_DIFFICULTY") # for unit test
    valid_pow?(block_hash, nonce, difficulty)
  end

  # Dark Gravity Wave history lookback for averaging (in blocks)
  HISTORY_LOOKBACK       =      24

  # SushiChain desired block spacing (in seconds)
  POW_TARGET_SPACING     = 120_f64

  # Plus or minus tolerance multiplier for acceptable block spacing
  POW_TIME_TOLERANCE     = 0.1_f64

  # Limits for how much of an individual block time will affect the running average
  HI_AVG_INCLUSION_LIMIT  = POW_TARGET_SPACING * 3_f64
  LOW_AVG_INCLUSION_LIMIT = POW_TARGET_SPACING * (1_f64 / 3_f64)

  # Difficulty value to be used when there is absolutely no history reference
  DEFAULT_DIFFICULTY_TARGET      = 13_i32

  def block_time_too_low(block_time : Float64) : Bool
    block_time < POW_TARGET_SPACING * (1_f64 - POW_TIME_TOLERANCE)
  end

  def block_time_too_high(block_time : Float64) : Bool
    block_time > POW_TARGET_SPACING * (1_f64 + POW_TIME_TOLERANCE)
  end

  def block_time_is_acceptable(block_time : Float64) : Bool
    return (!block_time_too_low(block_time)) && (!block_time_too_high(block_time))
  end

  def find_acceptable_difficulty_in_history(chain : Blockchain::Chain)
    i = chain.size - 1
    last_block_time = 0_i64
    while (i > chain.size - HISTORY_LOOKBACK) && (i > 0)
      block_reading = chain[i]
      if last_block_time > 0 
        elapsed = (last_block_time - block_reading.timestamp).to_f64
        if block_time_is_acceptable(elapsed)
          debug "Found a previous block(#{i}) that took #{elapsed} seconds to generate, using its difficulty value of #{block_reading.difficulty}"
          return block_reading.difficulty
        end
      end
      last_block_time = block_reading.timestamp
      i -= 1
    end
    return 0
  end

  def derive_difficulty_from_last_block(last_elapsed_time : Float64, last_difficulty : Int32)
    derived_difficulty = 0_i32
    if block_time_too_high(last_elapsed_time)
      derived_difficulty = last_difficulty - 1
      debug "Last block time of #{last_elapsed_time} is too high.. bumping difficulty down to #{derived_difficulty}"
    elsif block_time_too_low(last_elapsed_time)
      derived_difficulty = last_difficulty
      debug "Last block time of #{last_elapsed_time} is too low.. leave difficulty un-changed #{derived_difficulty} (only bump up via avg)"
    else
      derived_difficulty = last_difficulty
      debug "Last block time #{last_elapsed_time} is acceptable.. leave difficulty unchanged from #{derived_difficulty}"
    end
    return derived_difficulty
  end

  def find_acceptable_difficulty(chain : Blockchain::Chain, average_block_time : Float64) : Int32
    acceptable_difficulty = 0_i32
    last = chain.size - 1
    debug "Using last 2 block times for checking recent performance"
    last_elapsed_time = (chain[last].timestamp - chain[last - 1].timestamp).to_f64
    last_difficulty = chain[last].difficulty
    if block_time_is_acceptable(last_elapsed_time)
      debug "Most recent block time of #{last_elapsed_time} is acceptable.. using its difficulty of #{last_difficulty}"
      acceptable_difficulty = last_difficulty
    else
      debug "Most recent block time of #{last_elapsed_time} is not acceptable, looking for a previous block with acceptable block time"
      acceptable_difficulty = find_acceptable_difficulty_in_history(chain)
    end
    if acceptable_difficulty == 0
      if (average_block_time * 3_f64 < POW_TARGET_SPACING)
        acceptable_difficulty = last_difficulty + 1
        debug "Avg block time is less than one third of desired, bump difficulty to #{acceptable_difficulty}"
      else
        debug "No recent good block time was found, going to adjust difficulty based on last block's generation time"
        acceptable_difficulty = derive_difficulty_from_last_block(last_elapsed_time, last_difficulty)
      end
    end
    return acceptable_difficulty
  end
  
  def throttle_elapsed_time_difference(diff : Float64) : Float64
    diff =  LOW_AVG_INCLUSION_LIMIT if diff < LOW_AVG_INCLUSION_LIMIT
    diff =  HI_AVG_INCLUSION_LIMIT if diff > HI_AVG_INCLUSION_LIMIT
    diff
  end

  # Dark Gravity Wave based difficulty adjustment calculation (Original algorithm created by Evan Duffield)

  def block_difficulty(blockchain : Blockchain) : Int32
    actual_timespan = 0_f64
    last_block_time = 0_i64
    past_difficulty_avg = 0_f64
    past_difficulty_avg_prev = 0_f64
    
    # return difficulty from env var if it has be set
    return ENV["SC_SET_DIFFICULTY"].to_i if ENV.has_key?("SC_SET_DIFFICULTY")

    # return difficulty default target if doing e2e test
    return DEFAULT_DIFFICULTY_TARGET if ENV.has_key?("SC_E2E") # for e2e test

    # return difficulty default target if chain non-existant or not enough block history 
    chain = blockchain.chain
    debug "entered block_difficulty with chain length of #{chain.size}" if chain
    if !chain || chain.size < 2
      debug "entered block_difficulty with short initial chain (fewer than 2 blocks), returning default difficulty of #{DEFAULT_DIFFICULTY_TARGET}"
      return DEFAULT_DIFFICULTY_TARGET
    end

    if (chain.size < 5)
      last = chain.size - 1
      debug "Not enough historical data.. derive difficulty from performance of last block generation"
      last_elapsed_time = (chain[last].timestamp - chain[last - 1].timestamp).to_f64
      last_difficulty = chain[last].difficulty
      return derive_difficulty_from_last_block(last_elapsed_time, last_difficulty)
    end

    # construct an average difficulty from the historical blocks and calculate elapsed time of historical blocks
    count_blocks = 0
    oldest_history_spot = Math.max(chain.size - HISTORY_LOOKBACK, 1)
    i = oldest_history_spot
    debug "Oldest history spot: #{oldest_history_spot}"
    while i < chain.size
      block_reading = chain[i]
      if block_reading.timestamp > 0
        count_blocks += 1
        if count_blocks == 1
          past_difficulty_avg = block_reading.difficulty
        else
          past_difficulty_avg = ((past_difficulty_avg_prev * count_blocks)+(block_reading.difficulty)) / (count_blocks + 1).to_f64
        end
        past_difficulty_avg_prev = past_difficulty_avg
        if last_block_time > 0 
          diff = (block_reading.timestamp - last_block_time).to_f64
          debug "******** Block #{block_reading.index} was generated in #{diff} seconds with difficulty: #{block_reading.difficulty} ********"
          throttled_diff = throttle_elapsed_time_difference(diff)
          debug "Throttled generation time is #{throttled_diff}" if throttled_diff != diff
          actual_timespan += diff
        else
          debug "******** Looking at block #{block_reading.index} with difficulty #{block_reading.difficulty} and timestamp #{block_reading.timestamp} ******** "
        end
        last_block_time = block_reading.timestamp
      end
      i += 1
    end
    calculated_difficulty = past_difficulty_avg

    debug "Number of blocks in history lookback: #{count_blocks}"
    debug "calculated average difficulty: #{calculated_difficulty}"
    debug "calculated actual timespan: #{actual_timespan}"

    # calculate what the elapsed time for the historical block generation should have been
    target_timespan = count_blocks.to_f64 * POW_TARGET_SPACING

    # calculate average block time for the history block
    average_block_time = (actual_timespan / count_blocks).to_f64

    debug "calculated target timespan: #{target_timespan}"
    debug "average generation time per block: #{average_block_time} seconds"

    # return the best difficulty possible if the block average from the history lookback isn't acceptable
    if !block_time_is_acceptable(average_block_time)
      debug "average block time from Dark Gravity Wave is unacceptable, trying to find a difficulty that yields an acceptable block time"
      return find_acceptable_difficulty(chain, average_block_time)
    end

    # Calculate the new difficulty based on actual and target timespan.
    calculated_difficulty *= target_timespan
    calculated_difficulty /= actual_timespan
    debug "Difficulty adjusted by timespane #{calculated_difficulty}"

    calculated_difficulty_i32 = calculated_difficulty.round.to_i32

    debug "DGW calculated difficulty adjusted by timespans (and rounded): #{calculated_difficulty_i32}"

    calculated_difficulty_i32
  end


  include Hashes
end
