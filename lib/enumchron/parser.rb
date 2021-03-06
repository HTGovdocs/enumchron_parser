require 'parslet'

class Enumchron::Parser < Parslet::Parser

  def self.preprocess_line(l)
    l.chomp!                    # remove trailing cr
    l.downcase!                 # lowercase
    l.gsub!('*', '')            # asterisks to nothing
    l.gsub!(/\t/, ' ')          # tabs to spaces
    l.strip!                    # leading and trailing spaces
    l.gsub!(/[\.,:;\s]+\Z/, '') # trailing punctuation/space
    l
  end

  def initialize(*args)
    super
    lv_generator('number', 'numbers', 'nos', 'no', 'n')
    lv_generator('volume', 'volumes', 'vols', 'vol', 'vs', 'v')
    lv_generator('part', 'parts', 'pts', 'pt')
    lv_generator('copy', 'copies', 'cops', 'cop', 'cps', 'cp', 'c')
    lv_generator('series', 'series', 'ser', 'n.s', 'ns')
    lv_generator('report', 'reports', 'repts', 'rept', 'rep', 'r')
    lv_generator('section', 'section', 'sects', 'sect', 'secs', 'sec')
    lv_generator('appendix', 'appendices', 'apps', 'app')
    lv_generator('title', 'titles', 'ti', 't')

  end

  rule(:safe_letter) { match['abdefghijklmopqrsuwxyz']}

  # A generator for explicit label-value pairs: a label (vol, num, part, etc.) followed
  # by a list ()either a number_list or letter_list).

  def lv_generator(singular, plural, *abbr)
    text_sym     = "#{singular}_text".to_sym
    explicit_sym = "#{singular}_explicit".to_sym
    plural_sym   = "#{plural}".to_sym

    label_rule = str(plural) | str(singular)
    abbr_label = abbr.map { |a| str(a) }.inject(&:|)
    label      = label_rule | (abbr_label >> dot?)
    self.class.rule(explicit_sym) { label >> (lv_sep_plus_num | lv_sep_plus_char).as(plural_sym) }

    if @expl.nil?
      @expl = self.send(explicit_sym)
    else
      @expl = @expl | self.send(explicit_sym)
    end
  end

  rule(:space) { match('\s').repeat(1) }
  rule(:space?) { space.maybe }
  rule(:dot) { str('.') }
  rule(:dot?) { dot.maybe }
  rule(:digit) { match('\d') }
  rule(:natural_number) { match('[123456789]') }
  rule(:zero) { str('0') }
  rule(:zeros) { zero.repeat(1) }
  rule(:zeros?) { zeros.maybe }
  rule(:digits) { zeros? >> (natural_number >> digit.repeat(0)).as(:d) }
  rule(:digits?) { digits.maybe }
  rule(:letter) { match('[a-z]') }
  rule(:letters) { letter.repeat(1) }
  rule(:letters?) { letter.repeat(0) }
  rule(:dash) { str('-') }
  rule(:slash) { str('/') }
  rule(:lparen) { str('(') }
  rule(:rparen) { str(')') }
  rule(:colon) { str(':') }
  rule(:comma) { str(',') }
  rule(:plus) { str('+') }

  rule(:list_sep) { comma >> space? }
  rule(:range_sep) { space? >> dash >> space? }
  rule(:slash_sep) { space? >> slash >> space? }

  # What separates a label and its value? A colon, space, or nothing
  rule(:lv_num_sep) { colon >> space? | space? }
  rule(:lv_sep_plus_num) { lv_num_sep >> numerics }

  rule(:lv_char_sep) { colon >> space? | space }
  rule(:lv_sep_plus_char) {lv_char_sep >> letters }

  rule(:digits4) { digit.repeat(4) }
  rule(:digits2) { digit.repeat(2) }

  rule(:year4) { ((str('1') >> match['789']) | str('20')) >> digits2 }
  rule(:year2) { digits2 }
  rule(:year_end) { year4 | year2 }
  rule(:year_dual) { (year4.as(:start) >> slash >> year_end.as(:end)).as(:year_dual) }
  rule(:year_range) { (year4.as(:start) >> dash >> year_end.as(:end)).as(:year_range) }
  rule(:year_dual_range) { (year_dual.as(:start) >> range_sep >> (year_dual | year_end).as(:end)).as(:year_range) }
  rule(:year_list_component) { year_dual_range.as(:range) | year_range.as(:range) | year_dual.as(:dual) | year4.as(:single) }
  rule(:year_list) { year_list_component >> (list_sep >> year_list).repeat(0) }



  # A generic list of letters or letter-ranges
  # The kicker is that we can't have a "list" of letters without a delimiter;
  # we call that a "word" ;-)

  rule(:letter_range) { letter.as(:start) >> range_sep >> letter.as(:end) }
  rule(:letter_list_component) { letter_range.as(:range) | letter.as(:single) }
  rule(:letter_list) { letter_list_component >> (list_sep >> letter_list).repeat(1) }
  rule(:letters) { (letter_list | letter_list_component).as(:letters) }

  # A "safe" letter range starts with (or just consists of) a letter that is
  # not used by itself to indicate a named part (e.g. v for volume)

  rule(:safe_letter_list_component) { letter_range.as(:range) | safe_letter.as(:single) }
  rule(:safe_letter_list) { safe_letter_list_component >> (list_sep >> letter_list).repeat(1) }
  rule(:safe_letters) { (safe_letter_list | safe_letter_list_component).as(:letters) }



  # Same thing, but for numbers/ranges
  rule(:numeric_range) { digits.as(:start) >> range_sep >> digits.as(:end) }
  rule(:numeric_list_component) { numeric_range.as(:range) | digits.as(:single) }
  rule(:numeric_list) { numeric_list_component >> (list_sep >> numeric_list).repeat(0) }
  rule(:numerics) { numeric_list.as(:numeric) }

  # Again, but this time support number-letter combinations, like 4a-5b or
  # 4a-b. We can't really support 5a,b because of conflicts with things
  # like "no. 5a,v3" where the 'v' should mean 'volume'

  rule(:numlet) { digits.as(:numpart) >> letter_list_component.as(:letpart) }
  rule(:numlet_range) { numlet.as(:start) >> range_sep >> numlet.as(:end) }
  rule(:numlets) {(numlet_range.as(:range) | numlet.as(:single)).as(:numlets)}


  # Ordinals
  # We cheat; assume any digits followed by 'st', 'nd', 'rd', or 'th'
  rule(:ord_suffix) { str('st') | str('nd') | str('rd') | str('th') }
  rule(:ord) { digits.as(:num) >> ord_suffix }
  rule(:ord_range) { (ord | digits).as(:start) >> range_sep >> ord.as(:end) }
  rule(:ords) { (ord_range | ord).as(:ords) }

  # Months of the year
  rule(:jan) { str('january') | str('jan') >> dot? }
  rule(:feb) { str('february') | str('feb') >> dot? }
  rule(:mar) { str('march') | str('mar') >> dot? }
  rule(:apr) { str('april') | str('apr') >> dot? }
  rule(:may) { str('may') }
  rule(:jun) { str('june') | str('jun') >> dot? }
  rule(:jul) { str('july') | str('jul') >> dot? }
  rule(:aug) { str('august') | str('aug') >> dot? }
  rule(:sept) { str('september') | (str('sept') | str('sep')) >> dot? }
  rule(:oct) { str('october') | str('oct') >> dot? }
  rule(:nov) { str('november') | str('nov') >> dot? }
  rule(:dec) { str('december') | str('dec') >> dot? }

  rule(:month) { jan | feb | mar| apr | may | jun | jul | aug | sept | oct | nov | dec }
  rule(:month_range) { month.as(:start) >> (range_sep | slash_sep) >> month.as(:end) }
  rule(:month_list_component) { month_range.as(:range) | month.as(:single) }
  rule(:month_list) { month_list_component >> (list_sep >> month_list).repeat(1) }
  rule(:months) { (month_list | month_list_component).as(:months) }

  # Year/month, month/year

  rule(:ymsep) { space | (space? >> colon >> space?) }
  rule(:yearmonth) { (year_list.as(:years) >> ymsep >> months.as(:months)).as(:ym) }
  rule(:monthyear) { (months >> ymsep >> year_list.as(:years)).as(:ym) }

  # Seasons
  rule(:winter) { str('winter') | (str('wint') >> dot?) | (str('wtr') >> dot?) }
  rule(:summer) { str('summer') | str('summ') >> dot? }
  rule(:fall)   { str('fall') | str('autumn') | str('aut') }
  rule(:spring) { str('spring') | str('spr') >> dot? }
  rule(:season) { winter | spring | summer | fall }
  rule(:season_range) { season.as(:start) >> (range_sep | slash_sep) >> season.as(:end) }
  rule(:season_list_component) { season_range.as(:range) | season.as(:single) }
  rule(:season_list) { season_list_component >> (list_sep >> season_list).repeat(1) }
  rule(:seasons) { (season_list | season_list_component).as(:seasons) }

  # sudocs that start with 3 or 4
  rule(:sudocchar) { digit | colon | slash | dash }
  rule(:sudoc) { digit >> dot >> sudocchar.repeat(1) }


  # A supplement or an index just sitting by itself; sometimes it has a list
  rule(:suppl_label) { (str('supplement') | str('suppl') >> dot? | str('supp') >> dot?) }
  rule(:ind_label) { str('index') }
  rule(:suppl) { (suppl_label >> (lv_sep_plus_num | lv_sep_plus_char) | suppl_label).as(:suppl) }
  rule(:ind) { ((ind_label >> (lv_sep_plus_num | lv_sep_plus_char)) | ind_label).as(:index) }

  # Sometimes there's a "new series"
  rule(:ns) { (str('new series') | str('new ser.') | str('new ser') | str('n.s.')).as(:ns) }

  # ...or an indication that it's an annual summary instead of the real deal
  rule(:annual) { str('annual summaries') | str('annual summary') }

  # ...or a note that this is a revision (or has been revised???)
  rule(:rev) { str('revision') | str('rev') }

  # ...or a notation that its incomplete
  rule(:incomplete) { str('incomplete') | str('incompl') >> dot? }

  # An explicit year is one that includes a 'year' or 'yr'
  rule(:year_text) { str('year') | (str('yr') >> dot?) }
  rule(:year_explicit) { year_text >> lv_num_sep >> year_list.as(:eyears) }

  # .. and implicit if it doesn't
  rule(:year_implicit) { year_list.as(:iyears) }


  # The "explicit" rule is added to by lv_generator, which sets @expl
  rule(:explicit) { year_explicit | @expl }

  # Sometimes, there's an unknown list of letters or number and we
  # just don't know what it is

  rule(:unknown_list) { (numerics | letter_range.as(:range)).as(:unknown_list) }


  # The complete list of what we might find; too brittle to use yet
  #
  #rule(:all_comps) { ords |
  #    explicit |
  #    yearmonth | monthyear |
  #    year_implicit |
  #    ind | suppl | ns |
  #    seasons | months |
  #    annual | rev | incomplete |
  #    unknown_list }


  # The slam dunks, however, are almost always correct.
  # Add to this as things get better.

  rule(:slam_dunks) {
    explicit |
        year_implicit |
        months |
        ns | incomplete.as(:incompl)
  }

  rule(:comp) { slam_dunks | suppl | ind }

  rule(:ec_delim) { space? >> (comma | colon) >> space? | space }

  rule(:ec) { comp >> (ec_delim >> ec).repeat(1) | comp }

  rule(:ecp) { lparen >> space? >> ec >> space? >> rparen | ec }

  rule(:ecset) { ecp >> (ec_delim.maybe >> ecset).repeat(1) | ecp }

  rule(:ecset_or_sudoc) { sudoc.as(:sudoc) | ecset }


  root(:ecset_or_sudoc)
end
