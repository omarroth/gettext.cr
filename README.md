# gettext.cr

Crystal implementation of [gettext](https://www.gnu.org/software/gettext/manual/gettext.html). Exposes similar API to [Python `gettext`](https://docs.python.org/3/library/gettext.html) with additional support for `PO` files.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     gettext:
       github: omarroth/gettext.cr
   ```

2. Run `shards install`

## Usage

```crystal
require "gettext"

es_mo = Gettext::MoParser.new(File.open("examples/locales/es.mo"))
es_po = Gettext::PoParser.new(File.open("examples/locales/es.po"))

puts es_mo.ngettext("Time: %1 second", "Time: %1 seconds", 10) # => Czas: %1 sekundy
puts es_mo.ngettext("Time: %1 second", 10)                     # => Time: %1 second
puts es_po.ngettext("Time: %1 second", "Time: %1 seconds", 1)  # => Czas: %1 sekunda
puts es_po.ngettext("Time: %1 second", 1)                      # => Czas: %1 sekunda

translations = Gettext.find("examples/locales", nil)
puts translations.ngettext("es-US", "Time: %1 second", "Time: %1 seconds", 10) # => Czas: %1 sekundy
puts translations.gettext("es", "Logarithmic Scale")                           # => logaritamska skala

```

## Contributing

1. Fork it (<https://github.com/omarroth/gettext.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Omar Roth](https://github.com/omarroth) - creator and maintainer
