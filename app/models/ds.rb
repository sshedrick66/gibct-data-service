###############################################################################
## DS
## Provides standardization of length, conversion to ope6s from opes. OPE6 is 
## the 2, 3, 4, 5, and 6 digits of the 8 digit OPE. It also provides conversion
## for enumerated fields, boolean strings, and number discovery.
###############################################################################
module DS
  #############################################################################
  ## OpeId
  ## Provides coding for Ope ids in csvs.
  #############################################################################
  class OpeId
    ###########################################################################
    ## pad
    ## Pads ope ids to 8 characters by left-padding 0s
    ###########################################################################
    def self.pad(id)
      return id if id.blank? || id.downcase == "none"
      id.ljust(8, '0')
    end

    ###########################################################################
    ## to_ope6
    ## Converts an opeid to an ope 6 id.
    ###########################################################################
    def self.to_ope6(id)
      return id if id.blank? || id.downcase == "none" || id.length < 6

      id = pad(id)[1, 5]
    end

    ###########################################################################
    ## to_location
    ## Converts an opeid to an ope 6 id.
    ###########################################################################
    def self.to_location(id)
      return id if id.blank? || id.downcase == "none" || id.length < 6

      id = pad(id)
      id[0] + id[-2, 2]
    end
  end

  #############################################################################
  ## IpedsId
  ## Provides coding for Ipeds csvs.
  #############################################################################
  class IpedsId
    ###########################################################################
    ## pad
    ## Pads ope ids to 8 characters by left-padding 0s
    ###########################################################################
    def self.pad(id)
      return id if id.blank? || id.downcase == "none"
      id.ljust(6, '0')
    end

    ###########################################################################
    ## vetx_codes
    ## Coding for vetx fields in ipeds ic.
    ###########################################################################
    def self.vetx_codes
      [
        ['not applicable', -2], ['not reported', 1],
        ['implied no', 0], ['yes', 1]
      ]
    end

    ###########################################################################
    ## calsys_codes
    ## Coding for calsys field in ipeds ic.
    ###########################################################################
    def self.calsys_codes
      [
        ['not applicable', -2], ['semester', 1], ['quarter', 2], 
        ['trimester', 3], ['Four-one-four plan', 4], ['Other academic year', 5],
        ['Differs by program', 6], ['Continuous', 7]
      ]
    end

    ###########################################################################
    ## distncedx_codes
    ## Coding for distncedx_codes field in ipeds ic.
    ###########################################################################
    def self.distncedx_codes
      [
        ['not applicable', -2], ['not reported', -1], ['yes', 1], ['no', 2]
      ]
    end
  end

  #############################################################################
  ## Truth
  ## Normalalize truth values accross csvs.
  #############################################################################
  class Truth
    TRUTHS = ['yes', 'true', 't', 'y', '1', 'ye', 'tr', 'tru']

    ###########################################################################
    ## truthy?
    ## Returns true if value is a truthy value (converts to true).
    ###########################################################################
    def self.truthy?(value, nil_is_nil = true)
      return value if nil_is_nil && value.blank?
      
      TRUTHS.include?(value.try(:to_s).try(:strip).try(:downcase))
    end

    ###########################################################################
    ## yes
    ## Normalizes a string truth value to yes
    ###########################################################################
    def self.yes
      "yes"
    end


    ###########################################################################
    ## yes
    ## Normalizes a string false value to no
    ###########################################################################
    def self.no
      "no"
    end

    ###########################################################################
    ## value_to_truth
    ## Normalizes a string.
    ###########################################################################
    def self.value_to_truth(value)
      truthy?(value) ? yes : no
    end 
  end

  #############################################################################
  ## State
  ## Handles collection of states, normalizes states.
  #############################################################################
  class State
    STATES = { 
      "AK" => "Alaska", "AL" => "Alabama", "AR" => "Arkansas", 
      "AS" => "American Samoa", "AZ" => "Arizona",
      "CA" => "California", "CO" => "Colorado", "CT" => "Connecticut",
      "DC" => "District of Columbia", "DE" => "Delaware", 
      "FL" => "Florida", "FM" => "Federated States of Miconeisa",
      "GA" => "Georgia", "GU" => "Guam",
      "HI" => "Hawaii",
      "IA" => "Iowa", "ID" => "Idaho", "IDN" => "Indonesia", "IL" => "Illinois",
      "IN" => "Indiana",
      "KS" => "Kansas", "KY" => "Kentucky",
      "LA" => "Louisiana",
      "MA" => "Massachusetts", "MD" => "Maryland", "ME" => "Maine", "MH" => "Marshall Islands",
      "MI" => "Michigan", "MN" => "Minnesota", "MO" => "Missouri", "MP" => "Northern Mariana Islands",
      "MS" => "Mississippi", "MT" => "Montana",
      "NC" => "North Carolina", "ND" => "North Dakota",
      "NE" => "Nebraska", "NH" => "New Hampshire", "NJ" => "New Jersey",
      "NM" => "New Mexico", "NV" => "Nevada", "NY" => "New York",
      "OH" => "Ohio", "OK" => "Oklahoma", "OR" => "Oregon",
      "PA" => "Pennsylvania", "PR" => "Puerto Rico", "PW" => "Palau",
      "RI" => "Rhode Island", 
      "SC" => "South Carolina", "SD" => "South Dakota",
      "TN" => "Tennessee", "TX" => "Texas",
      "UT" => "Utah",
      "VA" => "Virginia", "VI" => "Virgin Islands", "VT" => "Vermont",
      "WA" => "Washington", "WI" => "Wisconsin",
      "WV" => "West Virginia",
      "WY" => "Wyoming"
    }

    ###########################################################################
    ## get_random_state
    ## Returns a randomly selected state_abbreviation => state_full_name
    ###########################################################################
    def self.get_random_state
      s = STATES.keys.sample
      { s => STATES[s] }
    end

    ###########################################################################
    ## []
    ## Returns the  name corresponding to the state name (abbreviation or
    ## full name).
    ###########################################################################
    def self.[](state_name)
      STATES[state_name.try(:upcase)] || get_abbr(state_name)
    end

    ###########################################################################
    ## get_abbr
    ## Returns the 2-character state abbreviation.
    ###########################################################################
    def self.get_abbr(state_name)
      name = state_name.split.map(&:capitalize).try(:join, " ")
      
      STATES.key(name) || state_name
    end

    ###########################################################################
    ## get_names
    ## Gets a list of state name abbreviations.
    ###########################################################################
    def self.get_names
      STATES.keys
    end

    ###########################################################################
    ## get_full_names
    ## Gets a list of full state names.
    ###########################################################################
    def self.get_full_names
      STATES.values
    end

    ###########################################################################
    ## get_as_options
    ## Gets a list of states in a form suitable of selects.
    ###########################################################################
    def self.get_as_options
      STATES.map { |name, full_name| [full_name, name] }
    end
  end

  #############################################################################
  ## Number
  ## Number tests and conversions.
  #############################################################################
  class Number
    ###########################################################################
    ## is_i?
    ## Returns true if the number is a fixnum or a fixnum string
    ###########################################################################
    def self.is_i?(value)
      value.is_a?(Fixnum) || (value =~ /\A[-+]?\d+\z/).present?
    end

    ###########################################################################
    ## is_f?
    ## Returns true if the number is a float, integer, integer string or a 
    ## fixnum string
    ###########################################################################
    def self.is_f?(value)
      value.is_a?(Float) || is_i?(value) || (value =~ /\A[-+]?\d*\.\d+\z/).present?
    end
  end
end