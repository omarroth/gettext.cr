require "./spec_helper"

describe Gettext do
  it "tests plural parser" do
    plural_parser = Gettext::PluralParser.new

    romantic_proc = ->(n : Int32) { (n != 1).to_unsafe }
    romantic_expression = plural_parser.parse("n != 1")
    Array.new(30) { |i| romantic_proc.call(i) }.should eq(Array.new(30) { |i| romantic_expression.call(i) })

    slavic_proc = ->(n : Int32) { n % 10 == 1 && n % 100 != 11 ? 0 : n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20) ? 1 : 2 }
    slavic_expression = plural_parser.parse("n % 10 == 1 && n % 100 != 11 ? 0 : n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20) ? 1 : 2")
    Array.new(30) { |i| slavic_proc.call(i) }.should eq(Array.new(30) { |i| slavic_expression.call(i) })
  end
end
