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
require "./welcome"

module ::Sushi::Core::Logger
  LL_VERBOSE = 0
  LL_DEBUG   = 1
  LL_INFO    = 2

  def log_level : Int32
    return LL_VERBOSE if ENV["SC_LOG"]? == "verbose"
    return LL_DEBUG if ENV["SC_LOG"]? == "debug"
    LL_INFO
  end

  def log_level_text : String
    case log_level
    when LL_VERBOSE
      return "verbose"
    when LL_DEBUG
      return "debug"
    when LL_INFO
      return "info"
    end

    "unknown"
  end

  def welcome
    return if ENV.has_key?("SC_UNIT") || ENV.has_key?("SC_INTEGRATION") || ENV.has_key?("SC_E2E") || ENV.has_key?("SC_FUNCTIONAL")
    puts welcome_message
  end

  def verbose(msg : String)
    return if ENV.has_key?("SC_UNIT") || ENV.has_key?("SC_INTEGRATION") || ENV.has_key?("SC_E2E") || ENV.has_key?("SC_FUNCTIONAL")
    return if log_level > LL_VERBOSE
    log_out("Verb", msg, :dark_gray)
  end

  def debug(msg : String)
    return if ENV.has_key?("SC_UNIT") || ENV.has_key?("SC_INTEGRATION") || ENV.has_key?("SC_E2E") || ENV.has_key?("SC_FUNCTIONAL")
    return if log_level > LL_DEBUG
    log_out("Debg", msg, :dark_gray)
  end

  def info(msg : String)
    return if ENV.has_key?("SC_UNIT") || ENV.has_key?("SC_INTEGRATION") || ENV.has_key?("SC_E2E") || ENV.has_key?("SC_FUNCTIONAL")
    return if log_level > LL_INFO
    log_out("Info", msg, :light_green)
  end

  def warning(msg : String)
    return if ENV.has_key?("SC_UNIT") || ENV.has_key?("SC_INTEGRATION") || ENV.has_key?("SC_E2E") || ENV.has_key?("SC_FUNCTIONAL")
    log_out("Warn", msg, :yellow)
  end

  def error(msg : String)
    log_out("Erro", msg, :red)
  end

  PROGRESS_BAR_WIDTH = 30

  PROGRESS_CHAR  = "\u{2593}"
  PROGRESS_CHARS = ["\u{2596}", "\u{2597}", "\u{2598}",
                    "\u{2599}", "\u{259A}", "\u{259B}",
                    "\u{259C}", "\u{259D}", "\u{259E}", "\u{259F}"]

  def progress(msg : String, current : Int, max : Int)
    return if ENV.has_key?("SC_UNIT") || ENV.has_key?("SC_E2E")
    return if max == 0

    ratio = (current * PROGRESS_BAR_WIDTH) / max

    bar_left = light_cyan(PROGRESS_CHAR * ratio)
    bar_right = ""

    (PROGRESS_BAR_WIDTH - ratio).times do |_|
      value = current % PROGRESS_CHARS.size
      value = 1 if value == 0
      bar_right += dark_gray(PROGRESS_CHARS[Random.rand(value)])
    end

    bar = "#{bar_left}#{bar_right}"

    print "#{bar} #{msg}\r"
  end

  private def log_out(t : String, msg : String, color : Symbol)
    puts "[ #{ftime} -- #{tag(t, color)} ] #{msg}"
  end

  private def tag(t : String, color : Symbol) : String
    ("%7s" % t).colorize.fore(color).to_s
  end

  private def ftime : String
    Time.now.to_s("%Y-%m-%d %H:%M:%S")
  end

  include Common::Color
  include Welcome
end
