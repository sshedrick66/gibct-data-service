require 'csv'

###############################################################################
## DataCsv
## Holds the merged data from CSV-sourced data tables, as well as methods to
## build, export, and push that data.
###############################################################################
class DataCsv < ActiveRecord::Base
  # GIBCT uses field called type, must kludge to prevent STI
  self.inheritance_column = "inheritance_type"

  validates :facility_code, presence: true, uniqueness: true
  validates :institution, presence: true

  validates :state, inclusion: { in: DS::State.get_names }, allow_blank: true

  ###########################################################################
  ## complete?
  ## Returns true only if all data_stores are populated in CsvStorage.
  ###########################################################################
  def self.complete?
    CsvFile::STI.keys.inject(true) do |s,a| 
      store = CsvStorage.find_by(csv_file_type: a)
      s = s && store.present? && store.data_store.present?
    end
  end  

  ###########################################################################
  ## setup_data_csv_table
  ## Sets up the Postgres environment prior to running a query, optionally
  ## causing the autosequencing of the ids to be reset and the created_at
  ## column to default to the current time. Nominally sets updated_at to
  ## default to the current time.
  ###########################################################################
  def self.setup_data_csv_table(for_weams = false)
    str = ""

    if for_weams
      str += "ALTER SEQUENCE data_csvs_id_seq RESTART WITH 1; "
      str += "ALTER TABLE data_csvs ALTER COLUMN created_at SET DEFAULT now(); "
    end

    str += "ALTER TABLE data_csvs ALTER COLUMN updated_at SET DEFAULT now(); "

    ActiveRecord::Base.connection.execute(str)
  end

  ###########################################################################
  ## restore_data_csv_table
  ## Drops defaults on the data_csv table.
  ###########################################################################
  def self.restore_data_csv_table(for_weams = false)
    str = "ALTER TABLE data_csvs ALTER COLUMN updated_at DROP DEFAULT; "
    str += "ALTER TABLE data_csvs ALTER COLUMN created_at DROP DEFAULT;" if for_weams

    ActiveRecord::Base.connection.execute(str)
  end

  ###########################################################################
  ## run_bulk_query
  ## Runs bulk query and provides support for created_at, updated_at, and
  ## renumbering autoincrements.
  ###########################################################################
  def self.run_bulk_query(query, for_weams = false)
    setup_data_csv_table(for_weams)
    ActiveRecord::Base.connection.execute(query)
    restore_data_csv_table(for_weams)
  end

  ###########################################################################
  ## build_data_csv
  ## Builds the data_csv table.
  ###########################################################################
  def self.build_data_csv
    return if !complete?

    initialize_with_weams
    update_with_crosswalk
    update_with_sva
    update_with_vsoc
    update_with_eight_key
    update_with_accreditation
    update_with_arf_gibill
    update_with_p911_tf
    update_with_p911_yr
    update_with_mou
    update_with_scorecard
    update_with_ipeds_ic
    update_with_ipeds_hd
    update_with_ipeds_ic_ay
    update_with_ipeds_ic_py
    update_with_sec702_school
    update_with_sec702
    update_with_settlement
    update_with_hcm
    update_with_complaint
    update_with_outcome
  end

  ###########################################################################
  ## to_csv
  ## Converts all the entries in the DataCsv to a csv row. Incorporates the
  ## required field ordering to be used by the VA EDU's data dashboard.
  ###########################################################################
  def self.to_csv
    CSV.generate do |csv|

      # Need to build csv in specific order for VA-EDU Dashboards
      cols = %W(
        facility_code institution city state zip country type correspondence 
        flight bah cross ope insturl vet_tuition_policy_url pred_degree_awarded 
        locale gibill undergrad_enrollment yr student_veteran student_veteran_link 
        poe eight_keys dodmou sec_702 vetsuccess_name vetsuccess_email 
        credit_for_mil_training vet_poc student_vet_grp_ipeds 
        soc_member va_highest_degree_offered retention_rate_veteran_ba 
        retention_all_students_ba retention_rate_veteran_otb
        retention_all_students_otb persistance_rate_veteran_ba 
        persistance_rate_veteran_otb graduation_rate_veteran 
        graduation_rate_all_students transfer_out_rate_veteran 
        transfer_out_rate_all_students salary_all_students 
        repayment_rate_all_students avg_stu_loan_debt calendar 
        tuition_in_state tuition_out_of_state books online_all 
        p911_tuition_fees p911_recipients p911_yellow_ribbon
        p911_yr_recipients accredited accreditation_type accreditation_status 
        caution_flag caution_flag_reason complaints_facility_code 
        complaints_financial_by_fac_code complaints_quality_by_fac_code 
        complaints_refund_by_fac_code complaints_marketing_by_fac_code
        complaints_accreditation_by_fac_code complaints_degree_requirements_by_fac_code
        complaints_student_loans_by_fac_code complaints_grades_by_fac_code
        complaints_credit_transfer_by_fac_code complaints_job_by_fac_code
        complaints_transcript_by_fac_code complaints_other_by_fac_code
        complaints_main_campus_roll_up complaints_financial_by_ope_id_do_not_sum
        complaints_quality_by_ope_id_do_not_sum complaints_refund_by_ope_id_do_not_sum
        complaints_marketing_by_ope_id_do_not_sum complaints_accreditation_by_ope_id_do_not_sum
        complaints_degree_requirements_by_ope_id_do_not_sum complaints_student_loans_by_ope_id_do_not_sum
        complaints_grades_by_ope_id_do_not_sum complaints_credit_transfer_by_ope_id_do_not_sum
        complaints_jobs_by_ope_id_do_not_sum complaints_transcript_by_ope_id_do_not_sum
        complaints_other_by_ope_id_do_not_sum
      )
      
      csv << cols

      all.order(:institution).each do |data|
        data["ope"] = ("'" + data["ope"] + "'") if data["ope"]
        data["type"] = data["type"].try(:upcase)
        csv << data.attributes.values_at(*cols).map { |v| v == false ? '' : v }
      end
    end
  end

  ###########################################################################
  ## to_gibct_institution_type
  ## Creates an institution type in the GIBCT for each unique type found in
  ## the data csv.
  ###########################################################################
  def self.to_gibct_institution_type(rows)
    GibctInstitutionType.delete_all

    types = rows.pluck(:type).uniq.inject({}) do |memo, type| 
      memo[type] = GibctInstitutionType.create(name: type).id
      memo
    end

    types
  end

  ###########################################################################
  ## gibct_institution_column_names
  ## Gets the institution column names whose values are copied from data_csv.
  ###########################################################################
  def self.gibct_institution_column_names
    names = GibctInstitution.column_names - %W(id created_at updated_at)
  end

  ###########################################################################
  ## partition_rows
  ## Partitions the data_csv row set into managable chunks. The largest
  ## number of parameters supported in sql prepares is 65536. Therefore if
  ## each row has k columns, and there are n rows
  ## number of rows (nrows) on a single sql prepare = 65536 / k 
  ## number of calls to prepare = rows.length / nrows 
  ###########################################################################
  def self.partition_rows(rows)
    cols = gibct_institution_column_names.length

    nrows = 65536 / cols
    ncalls = rows.length / nrows
    partitions = []

    # Insert data in 65536 column blocks
    ncalls.times { |i| partitions << (nrows * i .. nrows * (i + 1) - 1) }

    remaining_rows = nrows * ncalls < rows.length
    partitions << (nrows * ncalls .. (rows.length - 1)) if remaining_rows

    partitions
  end

  ###########################################################################
  ## map_value_to_type
  ## Maps the value of the DataCsv.column to a data type.
  ###########################################################################
  def self.map_value_to_type(value, type)
    case type
    when :integer
      value.to_i
    when :float
      value.to_f   
    when :string
      value.to_s if !value.nil?
    when :boolean
      if !value.nil?
        ["true", "t", "yes", "y", "1", "on"].include?(value.to_s.downcase)
      end
    else
      value
    end
  end
  ###########################################################################
  ## to_gibct_institution_type
  ## Creates an institution type in the GIBCT for each unique type found in
  ## the data csv.
  ###########################################################################
  def self.to_gibct_institution(rows, types, delete_table, config)  
    GibctInstitution.set_connection(config) 

    str = "ALTER TABLE institutions ALTER COLUMN created_at SET DEFAULT now(); "
    str += "ALTER TABLE institutions ALTER COLUMN updated_at SET DEFAULT now();"

    if delete_table
      GibctInstitution.delete_all
      str += "ALTER SEQUENCE institutions_id_seq RESTART WITH 1; "
    end

    GibctInstitution.connection.execute("#{str} BEGIN;")

    binds = []
    placeholders = []
    gibct_column_names = gibct_institution_column_names

    rows.each_with_index do |row, i|
      placeholder = []

      row = row.attributes

      row["ope"] = row["ope6"]
      row["institution_type_id"] = types[row["type"]]
      row.delete("type")

      gibct_column_names.each_with_index do |column, j|
        type = GibctInstitution.columns_hash[column].type
        value = map_value_to_type(row[column], type)

        binds << { value: value }
        placeholder << "$#{i * gibct_column_names.length + j + 1}"
      end

      placeholders << "(" + placeholder.join(", ") + ")"
    end

    str = "INSERT INTO institutions ("
    str += gibct_column_names.map { |c| %("#{c}") }.join(",") 
    str += ") "
    str += "VALUES " + placeholders.join(", ")

    raw = GibctInstitution.connection.raw_connection
    raw.prepare('gibctinsert', str)
    raw.exec_prepared('gibctinsert', binds)

    str = "COMMIT;"
    str += "ALTER TABLE institutions ALTER COLUMN updated_at DROP DEFAULT; "
    str += "ALTER TABLE institutions ALTER COLUMN created_at DROP DEFAULT; "
    GibctInstitution.connection.execute(str)

    GibctInstitution.remove_connection
  end

  ###########################################################################
  ## to_gibct
  ## Transfers data_csv entries to the GIBCT
  ###########################################################################
  def self.to_gibct(config = "./config/gibct_staging_database.yml")
    rows = DataCsv.all 

    GibctInstitutionType.set_connection(config) 
    GibctInstitution.set_connection(config) 

    types = to_gibct_institution_type(rows)
    partition = partition_rows(rows)

    GibctInstitution.remove_connection
    GibctInstitutionType.remove_connection

    partition.each_with_index do |p, i| 
      to_gibct_institution(rows[p], types, i == 0, config)
    end
  end

  ###########################################################################
  ## initialize_with_weams
  ## Initializes the DataCsv table with data from approved weams schools.
  ###########################################################################
  def self.initialize_with_weams
    DataCsv.delete_all

    names = Weam::USE_COLUMNS.map(&:to_s).join(', ')

    # Include only those schools marked as approved (c.f., Weam model)
    query = "INSERT INTO data_csvs (#{names}) ("
    query += Weam.select(names).where(approved: true).to_sql + ")"

    run_bulk_query(query, true)  
  end

  ###########################################################################
  ## update_with_crosswalk
  ## Updates the DataCsv table with data from the crosswalk.
  ###########################################################################
  def self.update_with_crosswalk
    names = VaCrosswalk::USE_COLUMNS.map(&:to_s)

    # Adds crosswalk info to approved schools, matching by facility_code.
    query_str = 'UPDATE data_csvs SET '
    query_str += names.map { |name| %("#{name}" = va_crosswalks.#{name}) }.join(', ')
    query_str += ' FROM va_crosswalks '
    query_str += 'WHERE data_csvs.facility_code = va_crosswalks.facility_code'    

    run_bulk_query(query_str)
  end

  ###########################################################################
  ## update_with_sva
  ## Updates the DataCsv table with data from the sva table.
  ###########################################################################
  def self.update_with_sva
    names = Sva::USE_COLUMNS.map(&:to_s)

    # Add SVA info to approved schools based on IPEDs id.
    query_str = 'UPDATE data_csvs SET '
    query_str += "student_veteran = TRUE, "
    query_str += names.map { |name| %("#{name}" = svas.#{name}) }.join(', ')
    query_str += ' FROM svas '
    query_str += 'WHERE data_csvs.cross = svas.cross '
    query_str += 'AND svas.cross IS NOT NULL'    

    run_bulk_query(query_str)
  end

  ###########################################################################
  ## update_with_vsoc
  ## Updates the DataCsv table with data from the vsoc table.
  ###########################################################################
  def self.update_with_vsoc
    names = Vsoc::USE_COLUMNS.map(&:to_s)

    # Adds Vets success info to approved schools, matching by facility_code.
    query_str = 'UPDATE data_csvs SET '
    query_str += names.map { |name| %("#{name}" = vsocs.#{name}) }.join(', ')
    query_str += ' FROM vsocs '
    query_str += 'WHERE data_csvs.facility_code = vsocs.facility_code'    

    run_bulk_query(query_str)
  end

  ###########################################################################
  ## update_with_eight_key
  ## Updates the DataCsv table with data from the eight_keys table.
  ###########################################################################
  def self.update_with_eight_key
    names = EightKey::USE_COLUMNS.map(&:to_s)

    # Adds 8-keys info to approved schools, matching by IPEDs id.
    query_str = 'UPDATE data_csvs SET '
    query_str += "eight_keys = TRUE "
    query_str += ' FROM eight_keys '
    query_str += 'WHERE data_csvs.cross = eight_keys.cross '
    query_str += 'AND eight_keys.cross IS NOT NULL'

    run_bulk_query(query_str)
  end

  ###########################################################################
  ## update_with_accreditation
  ## Updates the DataCsv table with data from the accreditations table. NOTE
  ## there is an explict ordering of both accreditation type and status for 
  ## those schools having conflicting types and statuses. The ordering is:
  ##
  ##   hybrid < national < regional
  ##
  ## and for status:
  ##
  ##   'show cause' < probation
  ##
  ## There is a requirement to include only those accreditations that are 
  ## institutional and currently active.
  ###########################################################################
  def self.update_with_accreditation
    # Sets all accreditations that are hybrid types first
    query_str = 'UPDATE data_csvs SET '
    query_str += 'accreditation_type = accreditations.accreditation_type'
    query_str += ' FROM accreditations '
    query_str += 'WHERE data_csvs.cross = accreditations.cross '
    query_str += 'AND accreditations.cross IS NOT NULL '    
    query_str += %(AND LOWER(accreditations.periods) LIKE '%current%' )
    query_str += %(AND LOWER(accreditations.csv_accreditation_type) = 'institutional' )
    query_str += "AND LOWER(accreditations.accreditation_type) = 'hybrid'; "

    # Sets all accreditations that are national, overriding conflicts with hybrids
    query_str += 'UPDATE data_csvs SET '
    query_str += 'accreditation_type = accreditations.accreditation_type'
    query_str += ' FROM accreditations '
    query_str += 'WHERE data_csvs.cross = accreditations.cross '
    query_str += 'AND accreditations.cross IS NOT NULL '    
    query_str += %(AND LOWER(accreditations.periods) LIKE '%current%' )
    query_str += %(AND LOWER(accreditations.csv_accreditation_type) = 'institutional' )
    query_str += "AND LOWER(accreditations.accreditation_type) = 'national'; "

    # Sets all accreditations that are regional, overriding conflicts with hybrids and nationals
    query_str += 'UPDATE data_csvs SET '
    query_str += 'accreditation_type = accreditations.accreditation_type'
    query_str += ' FROM accreditations '
    query_str += 'WHERE data_csvs.cross = accreditations.cross '
    query_str += 'AND accreditations.cross IS NOT NULL '    
    query_str += %(AND LOWER(accreditations.periods) LIKE '%current%' )
    query_str += %(AND LOWER(accreditations.csv_accreditation_type) = 'institutional' )
    query_str += "AND LOWER(accreditations.accreditation_type) = 'regional'; "

    # Sets status for probationary accreditations, the status being derived from the 
    # higest level of accreditation (hybrid, national, regional).
    query_str += 'UPDATE data_csvs SET '
    query_str += 'accreditation_status = accreditations.accreditation_status'
    query_str += ' FROM accreditations '
    query_str += 'WHERE data_csvs.cross = accreditations.cross '
    query_str += 'AND data_csvs.accreditation_type = accreditations.accreditation_type '
    query_str += 'AND accreditations.cross IS NOT NULL '
    query_str += %(AND LOWER(accreditations.periods) LIKE '%current%' )
    query_str += "AND LOWER(accreditations.csv_accreditation_type) = 'institutional' "
    query_str += "AND LOWER(accreditations.accreditation_status) = 'probation'; "

   # Sets status for show cause accreditations, overwriting probationary statuses, 
   # the status being derived from the higest level of accreditation (hybrid, national, regional).
    query_str += 'UPDATE data_csvs SET '
    query_str += 'accreditation_status = accreditations.accreditation_status'
    query_str += ' FROM accreditations '
    query_str += 'WHERE data_csvs.cross = accreditations.cross '
    query_str += 'AND data_csvs.accreditation_type = accreditations.accreditation_type '
    query_str += 'AND accreditations.cross IS NOT NULL '
    query_str += %(AND LOWER(accreditations.periods) LIKE '%current%' )
    query_str += "AND LOWER(accreditations.csv_accreditation_type) = 'institutional' "
    query_str += "AND LOWER(accreditations.accreditation_status) = 'show cause'; "

    # Sets the caution flag for all accreditations that have a non-null status. Note,
    # that institutional type accreditations are always, null, probation, or show cause.
    query_str += 'UPDATE data_csvs SET '
    query_str += 'caution_flag = TRUE'
    query_str += ' FROM accreditations '
    query_str += 'WHERE data_csvs.cross = accreditations.cross '
    query_str += 'AND accreditations.cross IS NOT NULL '
    query_str += %(AND LOWER(accreditations.periods) LIKE '%current%' )
    query_str += 'AND accreditations.accreditation_status IS NOT NULL '
    query_str += "AND LOWER(accreditations.csv_accreditation_type) = 'institutional'; "

    # Sets the caution flag reason for all accreditations that have a non-null status.
    # The innermost subquery retrieves a unique set of statues (it is plausible that
    # identical statuses may apply to the same school but from different agencies). We
    # don't want to repeat the same reasons. The outer subquery then concatentates these
    # unique reasons into a comma-separated string. Lastly the outer UPDATE-CASE appends
    # these caution flag reasons to any existing caution flag reasons.
    query_str += 'UPDATE data_csvs SET caution_flag_reason = '
    query_str += 'CASE WHEN data_csvs.caution_flag_reason IS NULL THEN '
    query_str += "  AGG.ad "
    query_str += "ELSE "
    query_str += "  CONCAT(data_csvs.caution_flag_reason, ', ', AGG.ad) "
    query_str += "END "
    query_str += "FROM ( "
    query_str += "  SELECT A.cross, string_agg(A.AST, ', ') AS ad "
    query_str += "    FROM ("
    query_str += "      SELECT a.cross, 'Accreditation (' || a.accreditation_status || ')' as AST"
    query_str += "      FROM accreditations a "
    query_str += "      WHERE "
    query_str += "        a.cross IS NOT NULL AND "
    query_str += "        a.accreditation_status IS NOT NULL AND "
    query_str += "        LOWER(a.periods) LIKE '%current%' AND "
    query_str += "        LOWER(a.csv_accreditation_type) = 'institutional' "
    query_str += "      GROUP BY a.cross, a.accreditation_status "
    query_str += "    ) A "
    query_str += "  GROUP BY A.cross "
    query_str += ") AGG "
    query_str += 'WHERE data_csvs.cross = AGG.cross; '

    run_bulk_query(query_str)
  end

  ###########################################################################
  ## update_with_arf_gibill
  ## Updates the DataCsv table with data from the arf_gibills table.
  ###########################################################################
  def self.update_with_arf_gibill
    names = ArfGibill::USE_COLUMNS.map(&:to_s)

    # Adds Gi Bill student counts to approved schools, matching by facility_code.
    query_str = 'UPDATE data_csvs SET '
    query_str += names.map { |name| %("#{name}" = arf_gibills.#{name}) }.join(', ')
    query_str += ' FROM arf_gibills '
    query_str += 'WHERE data_csvs.facility_code = arf_gibills.facility_code'

    run_bulk_query(query_str)
  end

  ###########################################################################
  ## update_with_p911_tf
  ## Updates the DataCsv table with data from the p911_tfs table.
  ###########################################################################
  def self.update_with_p911_tf
    names = P911Tf::USE_COLUMNS.map(&:to_s)

    # Adds Post 911 info to approved schools, matching by facility_code.
    query_str = 'UPDATE data_csvs SET '
    query_str += names.map { |name| %("#{name}" = p911_tfs.#{name}) }.join(', ')
    query_str += ' FROM p911_tfs '
    query_str += 'WHERE data_csvs.facility_code = p911_tfs.facility_code'

    run_bulk_query(query_str)
  end

  ###########################################################################
  ## update_with_p911_yr
  ## Updates the DataCsv table with data from the p911_yrs table.
  ###########################################################################
  def self.update_with_p911_yr
    names = P911Yr::USE_COLUMNS.map(&:to_s)

    # Adds Post 911 yellow-ribbon approved schools, matching by facility_code.
    query_str = 'UPDATE data_csvs SET '
    query_str += names.map { |name| %("#{name}" = p911_yrs.#{name}) }.join(', ')
    query_str += ' FROM p911_yrs '
    query_str += 'WHERE data_csvs.facility_code = p911_yrs.facility_code'

    run_bulk_query(query_str)
  end

  ###########################################################################
  ## update_with_mou
  ## Updates the DataCsv table with data from the mous table.
  ###########################################################################
  def self.update_with_mou
    names = Mou::USE_COLUMNS.map(&:to_s)
    reason = 'DoD Probation For Military Tuition Assistance'

    # Adds DOD memorandum of understanding for approved schools by ope6 id
    query_str = 'UPDATE data_csvs SET '
    query_str += names.map { |name| %("#{name}" = mous.#{name}) }.join(', ')
    query_str += ' FROM mous '
    query_str += 'WHERE data_csvs.ope6 = mous.ope6; '

    # Sets the caution flag for any approved school having a probatiton or 
    # title IV non-compliance (status == true)
    query_str += 'UPDATE data_csvs SET '
    query_str += 'caution_flag = TRUE'
    query_str += ' FROM mous '
    query_str += 'WHERE data_csvs.ope6 = mous.ope6 '
    query_str += 'AND mous.dod_status = TRUE; '
    
    # Sets the caution flag reason for any approved school having a probatiton or 
    # title IV non-compliance (status == true). The inner select sets the
    # caution flag text, ensuring there are not reasons (in case of multiple) 
    # memorandums. Lastly the outer UPDATE-CASE appends
    # these caution flag reasons to any existing caution flag reasons.
    query_str += 'UPDATE data_csvs SET caution_flag_reason = '
    query_str += 'CASE WHEN data_csvs.caution_flag_reason IS NULL THEN '
    query_str += "  AGG.am "
    query_str += "ELSE "
    query_str += "  CONCAT(data_csvs.caution_flag_reason, ', ', AGG.am) "
    query_str += "END "
    query_str += "FROM ( "
    query_str += "  SELECT M.ope6, '#{reason}'::text AS am "
    query_str += "    FROM ("
    query_str += "      SELECT m.ope6 "
    query_str += "      FROM mous m "
    query_str += "      WHERE m.dod_status = TRUE "
    query_str += "      GROUP BY m.ope6 "
    query_str += "    ) M "
    query_str += "  GROUP BY M.ope6 "
    query_str += ") AGG "
    query_str += 'WHERE data_csvs.ope6 = AGG.ope6; '

    run_bulk_query(query_str)
  end

  ###########################################################################
  ## update_with_scorecard
  ## Updates the DataCsv table with data from the scorecards table.
  ###########################################################################
  def self.update_with_scorecard
    names = Scorecard::USE_COLUMNS.map(&:to_s)

    # Adds scorecard data to approved schools, matching by IPEDs id.
    query_str = 'UPDATE data_csvs SET '
    query_str += names.map { |name| %("#{name}" = scorecards.#{name}) }.join(', ')
    query_str += ' FROM scorecards '
    query_str += 'WHERE data_csvs.cross = scorecards.cross'

    run_bulk_query(query_str)
  end

  ###########################################################################
  ## update_with_ipeds_ic
  ## Updates the DataCsv table with data from the IPEDs IC table.
  ###########################################################################
  def self.update_with_ipeds_ic
    names = IpedsIc::USE_COLUMNS.map(&:to_s)

    # Adds IC data to approved schools, matching by IPEDs id.
    query_str = 'UPDATE data_csvs SET '
    query_str += names.map { |name| %("#{name}" = ipeds_ics.#{name}) }.join(', ')
    query_str += ' FROM ipeds_ics '
    query_str += 'WHERE data_csvs.cross = ipeds_ics.cross'

    run_bulk_query(query_str)
  end

  ###########################################################################
  ## update_with_ipeds_hd
  ## Updates the DataCsv table with data from the IPEDs HD table.
  ###########################################################################
  def self.update_with_ipeds_hd
    names = IpedsHd::USE_COLUMNS.map(&:to_s)

    # Adds HD data to approved schools, matching by IPEDs id.
    query_str = 'UPDATE data_csvs SET '
    query_str += names.map { |name| %("#{name}" = ipeds_hds.#{name}) }.join(', ')
    query_str += ' FROM ipeds_hds '
    query_str += 'WHERE data_csvs.cross = ipeds_hds.cross'

    run_bulk_query(query_str)
  end

  ###########################################################################
  ## update_with_ipeds_ic_ay
  ## Updates the DataCsv table with data from the IPEDs IC AY table.
  ###########################################################################
  def self.update_with_ipeds_ic_ay
    names = IpedsIcAy::USE_COLUMNS.map(&:to_s)

    # Adds IC-AY data to approved schools, matching by IPEDs id.
    query_str = 'UPDATE data_csvs SET '
    query_str += names.map { |name| %("#{name}" = ipeds_ic_ays.#{name}) }.join(', ')
    query_str += ' FROM ipeds_ic_ays '
    query_str += 'WHERE data_csvs.cross = ipeds_ic_ays.cross'

    run_bulk_query(query_str)
  end

  ###########################################################################
  ## update_with_ipeds_ic_py
  ## Updates the DataCsv table with data from the IPEDs IC PY table. NOTE 
  ## that the information in this table (tution and book fees) are secondary 
  ## to the innformation contained tn the IPEDs IC AY.
  ###########################################################################
  def self.update_with_ipeds_ic_py
    names = IpedsIcPy::USE_COLUMNS.map(&:to_s)

    query_str = ""
    names.each do |name|
      # Update only where there are no IC AY values filled in.
      query_str += 'UPDATE data_csvs SET '
      query_str += %("#{name}" = ipeds_ic_pies.#{name})
      query_str += ' FROM ipeds_ic_pies '
      query_str += 'WHERE data_csvs.cross = ipeds_ic_pies.cross AND '
      query_str += "data_csvs.#{name} IS NULL; "
    end

    run_bulk_query(query_str)
  end

  ###########################################################################
  ## update_with_sec702_school
  ## Updates the DataCsv table with data from the sec 702 school table. NOTE
  ## the definition of NULL does not return true when NOT LIKE compared with  
  ## a string.
  ###########################################################################
  def self.update_with_sec702_school
    names = Sec702School::USE_COLUMNS.map(&:to_s)
    reason = 'Does Not Offer Required In-State Tuition Rates'

    # Only approved public schools can be SEC 702 complaint, matched by facility code
    query_str = 'UPDATE data_csvs SET '
    query_str += names.map { |name| %("#{name}" = sec702_schools.#{name}) }.join(', ')
    query_str += ' FROM sec702_schools '
    query_str += 'WHERE data_csvs.facility_code = sec702_schools.facility_code '
    query_str += 'AND sec702_schools.sec_702 IS NOT NULL '
    query_str += "AND lower(data_csvs.type) = 'public'; "

    # Any approved public school that is NOT sec 702 compliant sets the caution flag.
    query_str += 'UPDATE data_csvs SET '
    query_str += 'caution_flag = TRUE ' 
    query_str += ' FROM sec702_schools '
    query_str += 'WHERE data_csvs.facility_code = sec702_schools.facility_code '
    query_str += "AND sec702_schools.sec_702 = FALSE "
    query_str += "AND lower(data_csvs.type) = 'public'; "

    # Sets the caution flags for non compliant sec 702 public schools. The inner select 
    # chooses only those schools that are not sec 702 compliant. The outer select
    # concatenates these reasons into a comma delimited list for each school.
    # Lastly the outer UPDATE-CASE appends these caution flag reasons to any existing 
    # caution flag reasons.
    query_str += 'UPDATE data_csvs SET caution_flag_reason = '
    query_str += 'CASE WHEN data_csvs.caution_flag_reason IS NULL THEN '
    query_str += "  AGG.asr "
    query_str += "ELSE "
    query_str += "  CONCAT(data_csvs.caution_flag_reason, ', ', AGG.asr) "
    query_str += "END "
    query_str += "FROM ( "
    query_str += "  SELECT S.facility_code, '#{reason}'::text AS asr "
    query_str += "    FROM ("
    query_str += "      SELECT s.facility_code "
    query_str += "      FROM sec702_schools s"
    query_str += "      WHERE "
    query_str += "        s.sec_702 = FALSE"
    query_str += "      GROUP BY s.facility_code "
    query_str += "    ) S "
    query_str += "  GROUP BY S.facility_code "
    query_str += ") AGG "
    query_str += 'WHERE '
    query_str += "data_csvs.facility_code = AGG.facility_code AND lower(data_csvs.type) = 'public'; "

    run_bulk_query(query_str)
  end

  ###########################################################################
  ## update_with_sec702
  ## Updates the DataCsv table with data from the sec 702 table. This table
  ## details whether the public schools state-wide are sec 703 compliant. 
  ## this information is subordinate to the sec 702 info in the sec 703 
  ## school table.
  ###########################################################################
  def self.update_with_sec702
    names = Sec702::USE_COLUMNS.map(&:to_s)
    reason = 'Does Not Offer Required In-State Tuition Rates'

    query_str = ""
    names.each do |name|
      # Updates the sec 702 information only if there is no corresponding
      # entry from the sec 702 school table.
      query_str += 'UPDATE data_csvs SET '
      query_str += %("#{name}" = sec702s.#{name})
      query_str += ' FROM sec702s '
      query_str += 'WHERE data_csvs.state = sec702s.state '
      query_str += "AND data_csvs.#{name} IS NULL "
      query_str += "AND lower(data_csvs.type) = 'public'; "
    end

    # Updates the caution flag only if there is no corresponding flag
    # from the sec 702 school table.
    query_str += 'UPDATE data_csvs SET '
    query_str += 'caution_flag = TRUE ' 
    query_str += ' FROM sec702s '
    query_str += 'WHERE data_csvs.state = sec702s.state '
    query_str += "AND data_csvs.caution_flag IS NULL "
    query_str += "AND sec702s.sec_702 = FALSE "
    query_str += "AND lower(data_csvs.type) = 'public'; "

    # Sets the caution flags for non compliant sec 702 public schools. The inner select 
    # ensures the flag reason is only included once even of the state is listed
    # more than once. The where clause ensures only schools that do not have 
    # existing sec 702 school cautions are included. The outer select aggregates
    # these reasons in a comma delimited string that is then appended to the existing
    # caution flag reasons.
    query_str += 'UPDATE data_csvs SET caution_flag_reason = '
    query_str += 'CASE WHEN data_csvs.caution_flag_reason IS NULL THEN '
    query_str += "  AGG.asr "
    query_str += "ELSE "
    query_str += "  CONCAT(data_csvs.caution_flag_reason, ', ', AGG.asr) "
    query_str += "END "
    query_str += "FROM ( "
    query_str += "  SELECT S.state, '#{reason}'::text AS asr "
    query_str += "    FROM ("
    query_str += "      SELECT s.state "
    query_str += "      FROM sec702s s"
    query_str += "      WHERE "
    query_str += "        s.sec_702 = FALSE"
    query_str += "      GROUP BY s.state "
    query_str += "    ) S "
    query_str += "  GROUP BY S.state "
    query_str += ") AGG "
    query_str += 'WHERE '
    query_str += "  data_csvs.state = AGG.state AND "
    query_str += "  (data_csvs.caution_flag_reason NOT LIKE '%#{reason}%' OR "
    query_str += "  data_csvs.caution_flag_reason IS NULL) AND "
    query_str += "  lower(data_csvs.type) = 'public'; "

    run_bulk_query(query_str)
  end

  ###########################################################################
  ## update_with_settlement
  ## Updates the DataCsv table with data from the settlements table.
  ###########################################################################
  def self.update_with_settlement
    # Sets caution flags if the corresponing approved school (by IPEDs id) 
    # has an entry in the settlements table.
    query_str = 'UPDATE data_csvs SET '
    query_str += 'caution_flag = TRUE '
    query_str += ' FROM settlements '
    query_str += 'WHERE data_csvs.cross = settlements.cross; '

    # Sets the caution flag reason. The inner select ensures that the
    # settlement descriptions are unique for each school (There may be 
    # more than one per school). The outer select aggregates these 
    # reasons together in a comma delimited string that are appended to
    # the existing caution flag reasons.
    query_str += 'UPDATE data_csvs SET caution_flag_reason = '
    query_str += 'CASE WHEN data_csvs.caution_flag_reason IS NULL THEN '
    query_str += "  AGG.asd "
    query_str += "ELSE "
    query_str += "  CONCAT(data_csvs.caution_flag_reason, ', ', AGG.asd) "
    query_str += "END "
    query_str += "FROM ( "
    query_str += "  SELECT S.cross, string_agg(S.sd, ', ') AS asd "
    query_str += "    FROM ("
    query_str += "      SELECT s.cross, s.settlement_description AS sd"
    query_str += "      FROM settlements s "
    query_str += "      WHERE "
    query_str += "        s.cross IS NOT NULL AND "
    query_str += "        s.settlement_description IS NOT NULL "
    query_str += "      GROUP BY s.cross, s.settlement_description "
    query_str += "    ) S "
    query_str += "  GROUP BY S.cross "
    query_str += ") AGG "
    query_str += 'WHERE data_csvs.cross = AGG.cross'

    run_bulk_query(query_str)
  end

  ###########################################################################
  ## update_with_hcm
  ## Updates the DataCsv table with data from the hcm table.
  ###########################################################################
  def self.update_with_hcm
    # Sets caution flags if the corresponing approved school (by OPE6 id) 
    # has an entry in the Hcm table.
    query_str = 'UPDATE data_csvs SET '
    query_str += 'caution_flag = TRUE'
    query_str += ' FROM hcms '
    query_str += 'WHERE data_csvs.ope6 = hcms.ope6; '

    # Sets the caution flag reason for each school, by OPE6. The inner select
    # encloses unique reasons within a label while the outer select aggregates
    # the reasons into a comma delimited string. Lastly the outer UPDATE-CASE 
    # appends these caution flag reasons to any existing caution flag reasons.
    query_str += 'UPDATE data_csvs SET caution_flag_reason = '
    query_str += 'CASE WHEN data_csvs.caution_flag_reason IS NULL THEN '
    query_str += "  AGG.ahr "
    query_str += "ELSE "
    query_str += "  CONCAT(data_csvs.caution_flag_reason, ', ', AGG.ahr) "
    query_str += "END "
    query_str += "FROM ( "
    query_str += "  SELECT H.ope6, string_agg(H.hcmr, ', ') AS ahr "
    query_str += "    FROM ("
    query_str += "      SELECT h.ope6, 'Heightened Cash Monitoring (' || h.hcm_reason || ')' as hcmr"
    query_str += "      FROM hcms h "
    query_str += "      GROUP BY h.ope6, h.hcm_reason "
    query_str += "    ) H "
    query_str += "  GROUP BY H.ope6 "
    query_str += ") AGG "
    query_str += 'WHERE data_csvs.ope6 = AGG.ope6'

    run_bulk_query(query_str)
  end

  ###########################################################################
  ## update_with_complaint
  ## Updates the DataCsv table with data from the complaint table.
  ###########################################################################
  def self.update_with_complaint    
    names = Complaint::USE_COLUMNS.map(&:to_s)

    # Sets the complaint data for each school, matching by facility code.
    query_str = 'UPDATE data_csvs SET '
    query_str += names.map { |name| %("#{name}" = complaints.#{name}) }.join(', ')
    query_str += ' FROM complaints '
    query_str += 'WHERE data_csvs.facility_code = complaints.facility_code '

    # Transfer the complaints data to the data_csv, and then update all ope6
    # sums, since we have to do it for ALL rows in the data_csv.
    run_bulk_query(query_str)   
    Complaint.update_sums_by_ope6 
  end

  ###########################################################################
  ## update_with_outcome
  ## Updates the DataCsv table with data from the outcome table.
  ###########################################################################
  def self.update_with_outcome
    names = Outcome::USE_COLUMNS.map(&:to_s)

    # Sets the outcome data for each school, matching by facility code.
    query_str = 'UPDATE data_csvs SET '
    query_str += names.map { |name| %("#{name}" = outcomes.#{name}) }.join(', ')
    query_str += ' FROM outcomes '
    query_str += 'WHERE data_csvs.facility_code = outcomes.facility_code '

    run_bulk_query(query_str)    
  end
end
