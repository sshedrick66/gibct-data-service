class IpedsHdCsvFile < CsvFile
  HEADER_MAP = {
    "unitid" => :cross,
    "veturl" => :vet_tuition_policy_url
  }

  SKIP_LINES_BEFORE_HEADER = 0
  SKIP_LINES_AFTER_HEADER = 0

  DISALLOWED_CHARS = /[^#&'\w@:\- \.\/\(\)\+]/
  
  #############################################################################
  ## populate
  ## Reloads the accreditation table with the data in the csv data store
  #############################################################################  
  def populate
    old_logger = ActiveRecord::Base.logger
    ActiveRecord::Base.logger = nil

    begin
      write_data 
 
      rc = true
    rescue StandardError => e
      errors[:base] << e.message
      rc = false
    ensure
      ActiveRecord::Base.logger = old_logger    
    end

    return rc
  end
end