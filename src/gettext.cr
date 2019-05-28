# A Crystal implementation of gettext
# Copyright (C) 2019  Omar Roth
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

require "marpa"

# This is a little helper function that makes type inference easier.
# Since we need to call `to_unsafe` on booleans, we define the same
# function here for Int32 to avoid any extra handling.

struct Int32
  def to_unsafe
    self
  end
end

module Gettext
  # English singular, English plural, desired plural
  alias Msg = Tuple(String, String?, Int32)

  class PoActions < Marpa::Actions
    property catalog : Hash(Msg, String)
    property metadata : Hash(String, String)
    property plural : Proc(Int32, Int32)

    def initialize
      @catalog = {} of Msg => String
      @metadata = {} of String => String
      @plural = ->(x : Int32) { (x != 1).to_unsafe } # Germanic plural by default
    end

    def combine_string(context)
      context.flatten.join
    end

    def process_string(context)
      context[0].as(String)[1..-2]
    end

    def process_index(context)
      context[1].as(String)
    end

    def on_message(context)
      comments = context[0]
      msgctxt = context[1]
      msg = context[2][0].as(Array)[1].as(String)
      p_msg = context[2][0].as(Array)[2]?.try &.as(String)
      tmsg = context[3]

      # Handle metadata
      if msg.size == 0
        tmsg = tmsg[0].as(Array)[2].as(String)

        last_key = nil
        tmsg.split("\\n").each do |line|
          line = line.strip
          if line.empty?
            next
          end

          if line.includes? ":"
            key, value = line.split(":")
            key = key.strip.downcase
            value = value.strip

            @metadata[key] = value

            last_key = key
          elsif last_key
            @metadata[last_key] += "\n#{line}"
          end

          if !value
            next
          end

          case key
          when "plural-forms"
            value = value.split(";")
            @plural = PluralParser.parse(value[1].split("plural=")[1])
          end
        end
      else
        tmsg.as(Array).each_with_index do |translation, i|
          if index = translation[1].as?(String)
            i = index.to_i
          end

          @catalog[{msg, p_msg, i}] = translation[2].as(String)
        end
      end

      context
    end
  end

  abstract struct Locale
    property catalog : Hash(Msg, String)
    property metadata : Hash(String, String)
    property plural : Proc(Int32, Int32)

    def initialize
      @catalog = {} of Msg => String
      @metadata = {} of String => String
      @plural = ->(x : Int32) { (x != 1).to_unsafe } # Germanic plural by default
    end

    def gettext(message)
      if @catalog.has_key?({message, nil, 0}) && !@catalog[{message, nil, 0}].empty?
        return @catalog[{message, nil, 0}]
      else
        return message
      end
    end

    def ngettext(singular : String, n : Int32) : String
      ngettext(singular, nil, n)
    end

    def ngettext(singular : String, plural : String? = nil, n : Int32 = 1) : String
      index = @plural.as(Proc(Int32, Int32)).call(n)

      if @catalog.has_key?({singular, plural, index}) && !@catalog[{singular, plural, index}].empty?
        @catalog[{singular, plural, index}]
      elsif @catalog.has_key?({singular, plural, 0}) && !@catalog[{singular, plural, 0}].empty?
        @catalog[{singular, plural, 0}]
      elsif @catalog.has_key?({singular, nil, index}) && !@catalog[{singular, nil, index}].empty?
        @catalog[{singular, nil, index}]
      elsif @catalog.has_key?({singular, nil, 0}) && !@catalog[{singular, nil, 0}].empty?
        @catalog[{singular, nil, 0}]
      elsif n == 1 || !plural
        singular
      else
        plural
      end
    end
  end

  struct PoParser < Locale
    GETTEXT_BNF = <<-'END_BNF'
    :start ::= entries
    entries ::= entry*

    entry ::= comments msgctxt msgids msgstrs action => on_message
    comments ::= comment*

    comment ::= <translator comment>
    | <extracted comment>
    | reference
    | flag
    | <previous untranslated string>
    | <obselete message>

    <extracted comment> ~ /#\.[^\n]*/
    reference ~ /#:[^\n]*/
    flag ~ /#,[^\n]*/
    <previous untranslated string> ~ /#\|[^\n]*/
    <obselete message> ~ /#~[^\n]*/
    <translator comment> ~ /#[^\n]*/

    msgctxt ::= 'msgctxt' strings
    msgctxt ::=
    msgids ::= msgid msgid_plural
    msgid ::= 'msgid' strings
    msgid_plural ::= 'msgid_plural' strings
    msgid_plural ::=
    msgstrs ::= msgstr+
    msgstr ::= 'msgstr' optional_index strings
    optional_index ::= '[' number ']' action => process_index
    optional_index ::=

    strings ::= string+ action => combine_string
    string ::= /"([^"\\]|(\\[\d\D]))*"/ action => process_string
    number ~ [\d]+

    :discard ~ whitespace
    whitespace ~ [\s]+
    END_BNF

    def initialize(io : IO)
      initialize(io.gets_to_end)
    end

    def initialize(string : String)
      super()

      parse(string)
    end

    def parse(string, actions = PoActions.new)
      parser = Marpa::Parser.new
      grammar = parser.compile(GETTEXT_BNF).as(Marpa::Builder)
      parser.parse(string, grammar, actions)

      @catalog = actions.catalog
      @plural = actions.plural
      @metadata = actions.metadata
    end
  end

  class PluralActions < Marpa::Actions
    @stack = [] of Int32 -> Int32

    def number(context)
      @stack << ->(n : Int32) { context[0].as(String).to_i }
      context[0]
    end

    def n(context)
      @stack << ->(n : Int32) { n }
      context[0]
    end

    def parentheses(context)
      context[1]
    end

    def modulus(context)
      a, b = @stack.pop(2)
      @stack << ->(n : Int32) { a.call(n) % b.call(n) }
      context
    end

    def multiply(context)
      a, b = @stack.pop(2)
      @stack << ->(n : Int32) { a.call(n) * b.call(n) }
      context
    end

    def divide(context)
      a, b = @stack.pop(2)
      @stack << ->(n : Int32) { a.call(n) / b.call(n) }
      context
    end

    def add(context)
      a, b = @stack.pop(2)
      @stack << ->(n : Int32) { a.call(n) + b.call(n) }
      context
    end

    def subtract(context)
      a, b = @stack.pop(2)
      @stack << ->(n : Int32) { a.call(n) - b.call(n) }
      context
    end

    def less_than(context)
      a, b = @stack.pop(2)
      @stack << ->(n : Int32) { (a.call(n) < b.call(n)).to_unsafe }
      context
    end

    def less_than_or_equal_to(context)
      a, b = @stack.pop(2)
      @stack << ->(n : Int32) { (a.call(n) <= b.call(n)).to_unsafe }
      context
    end

    def greater_than(context)
      a, b = @stack.pop(2)
      @stack << ->(n : Int32) { (a.call(n) > b.call(n)).to_unsafe }
      context
    end

    def greater_than_or_equal_to(context)
      a, b = @stack.pop(2)
      @stack << ->(n : Int32) { (a.call(n) >= b.call(n)).to_unsafe }
      context
    end

    def equal_to(context)
      a, b = @stack.pop(2)
      @stack << ->(n : Int32) { (a.call(n) == b.call(n)).to_unsafe }
      context
    end

    def not_equal_to(context)
      a, b = @stack.pop(2)
      @stack << ->(n : Int32) { (a.call(n) != b.call(n)).to_unsafe }
      context
    end

    def logical_and(context)
      a, b = @stack.pop(2)
      @stack << ->(n : Int32) { ((a.call(n) == 1) && (b.call(n)) == 1).to_unsafe }
      context
    end

    def logical_or(context)
      a, b = @stack.pop(2)
      @stack << ->(n : Int32) { ((a.call(n) == 1) || (b.call(n) == 1)).to_unsafe }
      context
    end

    def ternary(context)
      a, b, c = @stack.pop(3)
      @stack << ->(n : Int32) { (a.call(n) == 1) ? b.call(n) : c.call(n) }
      context
    end
  end

  class PluralParser
    # https://en.wikipedia.org/wiki/Order_of_operations#Programming_languages
    PLURAL_BNF = <<-'END_BNF'
    :start ::= expression
    expression ::= number         action => number
    | 'n'                        action => n
    | '(' expression ')'         action => parentheses
    || expression '%'  expression action => modulus
    | expression '*'  expression action => multiply
    | expression '/'  expression action => divide
    || expression '+'  expression action => add
    | expression '-'  expression action => subtract
    || expression '<'  expression action => less_than
    | expression '<=' expression action => less_than_or_equal_to
    | expression '>'  expression action => greater_than
    | expression '>=' expression action => greater_than_or_equal_to
    || expression '==' expression action => equal_to
    | expression '!=' expression action => not_equal_to
    || expression '&&' expression action => logical_and
    || expression '||' expression action => logical_or
    | expression '?'  expression ':' expression action => ternary

    number ~ [\d]+

    :discard ~ whitespace
    whitespace ~ [\s]+
    END_BNF

    def initialize
      @parser = Marpa::Parser.new
      @grammar = @parser.compile(PLURAL_BNF).as(Marpa::Builder)
    end

    # Parse EXPRESSION
    def parse(string, actions = PluralActions.new)
      @parser.parse(string, @grammar, actions)
      actions.@stack[0] # => Expression as proc
    end

    def self.parse(string)
      parser = PluralParser.new
      parser.parse(string)
    end
  end

  struct MoParser < Locale
    LE_MAGIC = 0x950412de
    BE_MAGIC = 0xde120495

    def initialize(io)
      super()

      parse(io)
    end

    def parse(io)
      endianness = IO::ByteFormat::LittleEndian

      case version = io.read_bytes(UInt32, endianness)
      when LE_MAGIC
        endianness = IO::ByteFormat::LittleEndian
      when BE_MAGIC
        endianness = IO::ByteFormat::BigEndian
      else
        raise "Invalid magic"
      end

      version, msgcount, masteridx, transidx = Array.new(4) { |i| io.read_bytes(UInt32, IO::ByteFormat::LittleEndian) }
      if !{0, 1}.includes? version >> 16
        raise "Unsupported version"
      end

      msgcount.times do |i|
        io.seek(masteridx + i * 8)
        mlen, moff = Array.new(2) { |i| io.read_bytes(UInt32, endianness) }

        io.seek(transidx + i * 8)
        tlen, toff = Array.new(2) { |i| io.read_bytes(UInt32, endianness) }

        # Reference implementation https://github.com/python/cpython/blob/3.7/Lib/gettext.py
        # checks that msg and tmsg are bounded within the buffer, which we skip here

        io.seek(moff)
        msg = Bytes.new(mlen)
        io.read_utf8(msg)

        io.seek(toff)
        tmsg = Bytes.new(tlen)
        io.read_utf8(tmsg)

        # Handle metadata
        if mlen == 0
          last_key = nil

          String.new(tmsg).split("\n").each do |line|
            line = line.strip

            if line.empty?
              next
            end

            if line.includes? ":"
              key, value = line.split(":")
              key = key.strip.downcase
              value = value.strip

              @metadata[key] = value

              last_key = key
            elsif last_key
              @metadata[last_key] += "\n#{line}"
            end

            if !value
              next
            end

            case key
            when "content-type"
              io.set_encoding(value.split("charset=")[1].downcase)
            when "plural-forms"
              value = value.split(";")
              @plural = PluralParser.parse(value[1].split("plural=")[1])
            end
          end
        else
          if msg.includes? 0x00
            msgid1, msgid2 = String.new(msg).split("\u0000")
            tmsg = String.new(tmsg).split("\u0000")

            tmsg.each_with_index do |x, i|
              @catalog[{msgid1, msgid2, i}] = x
            end
          else
            @catalog[{String.new(msg), nil, 0}] = String.new(tmsg)
          end
        end
      end
    end
  end

  struct Translations
    alias Language = Tuple(String, String)
    property translations : Hash(Language, Locale)

    def initialize(localedir, languages : Array(String)? = nil)
      @translations = {} of Language => Locale

      find(localedir)
    end

    def find(localedir)
      Dir.each_child(localedir) do |child|
        case child
        when .ends_with? ".mo"
          @translations[getlanguage(child.rchop(".mo"))] = MoParser.new(File.open("#{localedir}/#{child}"))
        when .ends_with? ".po"
          @translations[getlanguage(child.rchop(".po"))] = PoParser.new(File.open("#{localedir}/#{child}"))
        else
          if Dir.exists?("#{localedir}/#{child}")
            find("#{localedir}/#{child}")
          end
        end
      end

      return translations
    end

    def getlanguage(string)
      if string.includes? "-"
        language, country = string.upcase.split("-")
        {language, country}
      elsif string.includes? "_"
        language, country = string.upcase.split("_")
        {language, country}
      else
        {string.upcase, ""}
      end
    end

    def ngettext(language : String, singular : String, plural : String?, n : Int32) : String
      ngettext(getlanguage(language), singular, plural, n)
    end

    def ngettext(language : Language, singular : String, plural : String? = nil, n : Int32 = 1) : String
      if @translations.has_key?(language)
        @translations[language].ngettext(singular, plural, n)
      elsif @translations.has_key?({language[0], ""})
        @translations[{language[0], ""}].ngettext(singular, plural, n)
      elsif n == 1 || !plural
        singular
      else
        plural
      end
    end

    def gettext(language : String, message : String) : String
      gettext(getlanguage(language), message)
    end

    def gettext(language : Language, message : String) : String
      if @translations.has_key?(language)
        @translations[language].gettext(message)
      elsif @translations.has_key?({language[0], ""})
        @translations[{language[0], ""}].gettext(message)
      else
        message
      end
    end
  end

  def self.find(localedir, languages : Array(String)? = nil)
    return Translations.new(localedir, languages)
  end
end
