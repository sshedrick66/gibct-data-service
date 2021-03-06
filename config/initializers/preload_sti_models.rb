##############################################################################
## Preloads all Single Table Inheritance (STI) classes in development, rather 
## than lazy loading. The parent class needs to recognize its children ASAP.
## These dependencies reflect the *CsvFile classes that are responsible for
## uploading CSV files and population their associated intermediate data
## tables. These are the tables used to populate the final data_csvs table.
##############################################################################
if Rails.env.development? || Rails.env.test?
	# Preload all raw file subclasses - Weams MUST be last ...	
  %w(
    csv_file accreditation_csv_file arf_gibill_csv_file complaint_csv_file 
    eight_key_csv_file hcm_csv_file ipeds_ic_csv_file ipeds_ic_ay_csv_file 
    ipeds_ic_py_csv_file ipeds_hd_csv_file mou_csv_file p911_tf_csv_file 
    outcome_csv_file p911_yr_csv_file scorecard_csv_file 
    sec702_school_csv_file sec702_csv_file settlement_csv_file sva_csv_file 
    va_crosswalk_csv_file vsoc_csv_file weams_csv_file 
  ).each do |c|
		require_dependency Rails.root.join("app", "models/csv_files/#{c}.rb")
  end
end