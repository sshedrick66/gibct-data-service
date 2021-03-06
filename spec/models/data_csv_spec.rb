require 'rails_helper'

RSpec.describe DataCsv, type: :model do
  #############################################################################
  ## Common Definitions
  #############################################################################
  let!(:weam_approved_public) { create :weam, :public, state: 'NY', institution: "O'MALLEY SCHOOL" }
  let!(:weam_approved_private) { create :weam, :private, state: 'NJ', institution: 'THE # SIGN SCHOOL' }
  let!(:weam_unapproved) { create :weam, :non_approved_poo, state: 'OH' }
  let!(:weam_unmatched) { create :weam, state: 'CA' }

  let!(:crosswalk_approved_public) do
    create :va_crosswalk, facility_code: weam_approved_public.facility_code 
  end

  let!(:crosswalk_approved_private) do
    create :va_crosswalk, facility_code: weam_approved_private.facility_code 
  end

  let!(:crosswalk_unapproved) do
    create :va_crosswalk, facility_code: weam_unapproved.facility_code 
  end

  let!(:crosswalk_unmatched) do
    create :va_crosswalk, facility_code: weam_unmatched.facility_code 
  end

  #############################################################################
  ## Common Setup
  #############################################################################
  before(:each) do
    DataCsv.initialize_with_weams 
    DataCsv.update_with_crosswalk 
  end

  #############################################################################
  ## complete?
  #############################################################################
  describe 'complete?' do
    context 'when some csv_files are missing' do
      it 'is false' do
        expect(DataCsv).not_to be_complete
      end
    end

    context 'when all csv_files are present' do
      it 'is true' do
        CsvFile::STI.keys.each do |t| 
          cs = CsvStorage.create(csv_file_type: t, data_store: 'a')
        end

        expect(DataCsv).to be_complete
      end
    end
  end

  #############################################################################
  ## build_data_csv
  #############################################################################
  describe 'build_data_csv' do
    context 'when complete' do
      before(:each) do
        CsvFile::STI.keys.each { |k| create k.underscore.to_sym }
      end

      it 'calls all initialize and update methods' do
        [
          :initialize_with_weams, :update_with_crosswalk, :update_with_sva,
          :update_with_vsoc, :update_with_eight_key, 
          :update_with_accreditation, :update_with_arf_gibill, 
          :update_with_p911_tf, :update_with_p911_yr, :update_with_mou, 
          :update_with_scorecard, :update_with_ipeds_ic, :update_with_ipeds_hd, 
          :update_with_ipeds_ic_ay, :update_with_ipeds_ic_py,
          :update_with_sec702_school, :update_with_sec702, 
          :update_with_settlement, :update_with_hcm, :update_with_complaint,
          :update_with_outcome
        ].each do |m|
          expect(DataCsv).to receive(m)
        end
        
        DataCsv.build_data_csv
      end

      it 'adds instances to the DataCsv table' do
        expect{ DataCsv.build_data_csv }.to change{ DataCsv.count }
      end
    end

    context 'when not complete' do
      it 'does nothing' do
        expect{ DataCsv.build_data_csv }.not_to change{ DataCsv.count }
      end
    end
  end

  #############################################################################
  ## to_csv
  #############################################################################
  describe 'to_csv' do
    before(:each) do
      CsvFile::STI.keys.each { |k| create k.underscore.to_sym }

      Weam.first.update(attributes_for :weam, :public)
      DataCsv.build_data_csv
    end

    it 'calls CSV.generate' do
      expect(CSV).to receive(:generate)
      DataCsv.to_csv
    end

    it 'produces a header row + 1 row per DataCsv instance' do
      expect(DataCsv.to_csv.lines.length).to eq(DataCsv.count + 1)
    end
  end

  #############################################################################
  ## to_gibct
  #############################################################################
  describe 'to_gibct_institution_type' do
    let (:test_connection) { './config/gibct_staging_database.yml' }

    before(:each) do
      # Load test csv files so there is information to work with
      CsvFile::STI.keys.each { |k| create k.underscore.to_sym }

      Weam.first.update(attributes_for :weam, :public)
      DataCsv.build_data_csv
      
      # Use this connection to test remote GIBCT DB
      GibctInstitutionType.set_connection(test_connection)

      DataCsv.to_gibct_institution_type(DataCsv.all)
    end

    after(:each) do
      GibctInstitutionType.remove_connection
    end

    it 'adds an institution type to the Gibct for each type in data_csv' do
      expect(GibctInstitutionType.pluck(:name)).to match_array(DataCsv.pluck(:type))
    end
  end

  #############################################################################
  ## to_gibct
  #############################################################################
  describe 'to_gibct' do
    let (:test_connection) { './config/gibct_staging_database.yml' }

    before(:each) do
      CsvFile::STI.keys.each { |k| create k.underscore.to_sym }

      Weam.first.update(attributes_for :weam, :public)
      DataCsv.build_data_csv

      DataCsv.to_gibct
      
      GibctInstitutionType.set_connection('./config/gibct_staging_database.yml')
      GibctInstitution.set_connection('./config/gibct_staging_database.yml')
    end

    after(:each) do
      GibctInstitution.remove_connection
      GibctInstitutionType.remove_connection
    end

    it 'adds an institution type to the Gibct for each type in data_csv' do
      expect(GibctInstitutionType.count).to eq(2)
      expect(GibctInstitutionType.pluck(:name)).to match_array(DataCsv.pluck(:type))
    end

    it 'adds an institution to the Gibct for each institution in data_csv' do
      expect(GibctInstitution.count).to eq(2)
      expect(GibctInstitution.pluck(:institution)).to match_array(DataCsv.pluck(:institution))
    end
  end

  #############################################################################
  ## gibct_institution_column_names
  #############################################################################
  describe 'gibct_institution_column_names' do
    let (:test_connection) { './config/gibct_staging_database.yml' }

    before(:each) do
      CsvFile::STI.keys.each { |k| create k.underscore.to_sym }

      Weam.first.update(attributes_for :weam, :public)
      DataCsv.build_data_csv
     
      GibctInstitution.set_connection(test_connection)
    end

    after(:each) do
      GibctInstitution.remove_connection
    end

    it 'gets the column names of the fields in the GIBCT institution table' do
      expect(DataCsv.gibct_institution_column_names.count).to be > 0
      expect(DataCsv.gibct_institution_column_names).to include('facility_code')        
      expect(DataCsv.gibct_institution_column_names).to include('institution_type_id')        
    end

    it 'does not include id, created_at, or updated at' do
      expect(DataCsv.gibct_institution_column_names).not_to include('id', 'created_at', 'updated_at')        
    end
  end

  #############################################################################
  ## partition_rows
  #############################################################################
  describe 'partition_rows' do
    let(:max_block_rows) { 65536 / DataCsv.gibct_institution_column_names.length }
    let (:test_connection) { './config/gibct_staging_database.yml' }

    before(:each) do
      CsvFile::STI.keys.each { |k| create k.underscore.to_sym }

      Weam.first.update(attributes_for :weam, :public)
      DataCsv.build_data_csv
     
      GibctInstitution.set_connection(test_connection)
    end

    after(:each) do
      GibctInstitution.remove_connection
    end

    it 'partitions data_csv into a single block if there are less than 65K attributes' do
      expect(DataCsv.partition_rows(DataCsv.all)).to eq([0 .. 1])

      filler =  max_block_rows - DataCsv.count
      filler = 0 if filler < 0

      create_list :weam, filler, :public
      DataCsv.build_data_csv

      expect(DataCsv.partition_rows(DataCsv.all)).to eq([0 .. max_block_rows - 1])        
    end

    it 'partitions data_csv into a multiple blocks if there are more than 65K attributes' do
      filler =  max_block_rows - DataCsv.count + 1
      filler = 0 if filler < 0

      create_list :weam, filler, :public
      DataCsv.build_data_csv

      expect(DataCsv.partition_rows(DataCsv.all)).to eq([
        0 .. max_block_rows - 1, max_block_rows .. DataCsv.count - 1
      ])                
    end
  end

  ###########################################################################
  ## map_value_to_type
  ###########################################################################
  describe 'map_value_to_type' do
    it 'maps nil to nil' do
      expect(DataCsv.map_value_to_type(nil, :nil)).to be_nil
    end

    context 'maps to boolean' do
      it 'maps nil to nil' do
        expect(DataCsv.map_value_to_type(nil, :boolean)).to be_nil
      end

      it 'maps 1 to true' do
        expect(DataCsv.map_value_to_type(1, :boolean)).to be_truthy
      end

      it 'maps != 1 to false' do
        expect(DataCsv.map_value_to_type(2, :boolean)).to be_falsy
      end

      it 'maps booleans to booleans' do
        expect(DataCsv.map_value_to_type(true, :boolean)).to be_truthy
        expect(DataCsv.map_value_to_type(false, :boolean)).to be_falsy
      end

      it 'maps boolean type strings to booleans' do
        %W(TRUE true T t Y y YES yes ON on 1).each do |v|
          expect(DataCsv.map_value_to_type(v, :boolean)).to be_truthy
        end

        %W(FALSE false F f N n NO no OFF off 0 2).each do |v|
          expect(DataCsv.map_value_to_type(v, :boolean)).to be_falsy
        end

        expect(DataCsv.map_value_to_type('', :boolean)).to be_falsy
      end
    end

    context 'maps to integer' do
      it 'maps nil to 0' do
        expect(DataCsv.map_value_to_type(nil, :integer)).to eq(0)
      end

      it 'maps blank to 0' do
        expect(DataCsv.map_value_to_type('', :integer)).to eq(0)
      end

      it 'maps strings to integers' do
        expect(DataCsv.map_value_to_type('1', :integer)).to eq(1)
        expect(DataCsv.map_value_to_type('0', :integer)).to eq(0)
        expect(DataCsv.map_value_to_type('-1', :integer)).to eq(-1)
      end

      it 'maps numbers to integers' do
        expect(DataCsv.map_value_to_type(1, :integer)).to eq(1)
        expect(DataCsv.map_value_to_type(1.0, :integer)).to eq(1)
      end
    end

    context 'maps to float' do
      it 'maps nil to 0.0' do
        expect(DataCsv.map_value_to_type(nil, :float)).to eq(0.0)
      end

      it 'maps blank to 0' do
        expect(DataCsv.map_value_to_type('', :float)).to eq(0.0)
      end

      it 'maps strings to numbers' do
        expect(DataCsv.map_value_to_type('1', :float)).to eq(1.0)
        expect(DataCsv.map_value_to_type('-1.0', :float)).to eq(-1.0)
        expect(DataCsv.map_value_to_type('0', :integer)).to eq(0.0)
      end
    end

    context 'maps to string' do
      it 'maps nil to nil' do
        expect(DataCsv.map_value_to_type(nil, :string)).to be_nil
      end

      it 'maps blank to blank' do
        expect(DataCsv.map_value_to_type('', :string)).to eq('')
      end

      it 'maps numbers to strings' do
        expect(DataCsv.map_value_to_type(1, :string)).to eq('1')
        expect(DataCsv.map_value_to_type(-1.0, :string)).to eq('-1.0')
      end

      it 'maps strings to strings' do
        expect(DataCsv.map_value_to_type('abc', :string)).to eq('abc')
      end
    end
  end

  #############################################################################
  ## initialize_with_weams
  #############################################################################
  describe 'initialize_with_weams' do
    let(:fcs) { DataCsv.all.pluck(:facility_code) }

    describe 'an institution' do
      context 'that is approved' do
        it 'is copied to the data_csv' do
          expect(fcs).to contain_exactly(
            weam_approved_public.facility_code,
            weam_approved_private.facility_code,
            weam_unmatched.facility_code
          )  
        end
      end

      context 'that is not approved' do
        it 'is not copied to the data_csv' do
          expect(fcs).not_to include(weam_unapproved.facility_code)
        end
      end
    end

    describe "when copying fields to data_csv" do
      Weam::USE_COLUMNS.each do |column|
        it "sets the #{column} column" do
          DataCsv.all.each do |data|
            weam = Weam.find_by(facility_code: data.facility_code)
            expect(data[column]).to eq(weam[column])
          end
        end
      end
    end
  end

  #############################################################################
  ## update_with_crosswalk
  #############################################################################
  describe "update_with_crosswalk" do  
    let(:approved) do 
      [
        crosswalk_approved_public, 
        crosswalk_approved_private, 
        crosswalk_unmatched
      ]
    end 

    describe "when matching" do
      it "matches facility_code to approved schools in data_csv" do
        approved.each do |crosswalk|
          data = DataCsv.find_by(facility_code: crosswalk.facility_code)
          expect(data).not_to be_nil
        end
      end

      it "dosen't match to unnapproved schools" do
        data = DataCsv.find_by(facility_code: crosswalk_unapproved.facility_code)
        expect(data).to be_nil
      end
    end

    describe "when copying fields to data_csv" do
      VaCrosswalk::USE_COLUMNS.each do |column|
        it "updates the #{column} column" do
          DataCsv.all.each do |data|
            crosswalk = VaCrosswalk.find_by(facility_code: data.facility_code)
            expect(data[column]).to eq(crosswalk[column])
          end
        end
      end
    end
  end

  #############################################################################
  ## update_with_sva
  #############################################################################
  describe "update_with_sva" do
    let!(:sva) { create :sva, cross: crosswalk_approved_public.cross }
    let!(:sva_nil_cross) { create :sva, cross: nil, institution: "nilcross" }

    let(:data) { DataCsv.find_by(cross: sva.cross) }

    before(:each) do
      DataCsv.update_with_sva
    end

    describe "when matching" do
      it "matches cross to approved schools in data_csv" do
        expect(data).not_to be_nil

        data = DataCsv.find_by(cross: sva_nil_cross.cross)
        expect(data).to be_nil    
      end
    end

    describe "when copying fields to data_csv" do
      Sva::USE_COLUMNS.each do |column|
        it "updates the #{column} column" do
          expect(data[column]).to eq(sva[column])
        end
      end

      it "updates data_csv.student_veteran to true" do
        expect(data.student_veteran).to be_truthy
      end
    end
  end

  #############################################################################
  ## update_with_vsoc
  #############################################################################
  describe "update_with_vsoc" do
    let!(:vsoc) do 
      create :vsoc, facility_code: crosswalk_approved_public.facility_code 
    end

    let(:data) { DataCsv.find_by(facility_code: vsoc.facility_code) }

    before(:each) do
      DataCsv.update_with_vsoc
    end

    describe "when matching" do
      it "matches facility_code to approved schools in data_csv" do
        expect(data).not_to be_nil
      end
    end

    describe "when copying fields to data_csv" do
      Vsoc::USE_COLUMNS.each do |column|
        it "updates the #{column} column" do
          expect(data[column]).to eq(vsoc[column])
        end
      end
    end
  end

  #############################################################################
  ## update_with_eight_key
  #############################################################################
  describe "update_with_eight_key" do
    let!(:eight_key) do 
      create :eight_key, cross: crosswalk_approved_public.cross 
    end

    let!(:eight_key_nil_cross) { create :eight_key, cross: nil }

    let(:data) { DataCsv.find_by(cross: eight_key.cross) }

    before(:each) do
      DataCsv.update_with_eight_key
    end

    describe "when matching" do
      it "matches cross to approved schools in data_csv" do
        expect(data).not_to be_nil

        data = DataCsv.find_by(cross: eight_key_nil_cross)
        expect(data).to be_nil        
      end
    end

    describe "when copying fields to data_csv" do
      it "updates data_csv.eight_key to true" do
        expect(data.eight_keys).to be_truthy
      end
    end
  end

  #############################################################################
  ## update_with_accreditation
  #############################################################################
  describe "update_with_accreditation" do
    describe "when matching" do
      context "and accreditation is institutional and current" do
        let(:data) { DataCsv.find_by(cross: accreditation.cross) }

        let!(:accreditation) do 
          create :accreditation, 
            campus_ipeds_unitid: crosswalk_approved_public.cross
        end

        let!(:accreditation_nil_cross) do 
          create :accreditation, campus_ipeds_unitid: nil
        end

        before(:each) do
          DataCsv.update_with_accreditation
        end

        it "matches cross to approved schools in data_csv" do
          expect(data).not_to be_nil

          data = DataCsv.find_by(cross: accreditation_nil_cross.cross)
          expect(data).to be_nil
        end
      end

      [:not_institutional, :not_current].each do |trait|
        context "and is #{trait.to_s.humanize.downcase}" do
          let(:data) { DataCsv.find_by(cross: accreditation.cross) }

          let!(:accreditation) do 
            create :accreditation, trait,
              campus_ipeds_unitid: crosswalk_approved_public.cross
          end

          before(:each) do
            DataCsv.update_with_accreditation
          end

          Accreditation::USE_COLUMNS.each do |column|
            it "does not match #{column} to approved schools in data_csv" do
              expect(data[column]).to be_nil
            end
          end
        end
      end
    end

    describe 'when building accreditation_type' do
      context 'and data_csvs.accreditation_type is NULL' do
        { 
          'ACUPUNCTURE HYBRID' => 'HYBRID', 
          'BIBLICAL NATIONAL' => 'NATIONAL', 
          'MIDDLE REGIONAL' => 'REGIONAL'
        }.each_pair do |agency, type|
          it "sets the data_csvs.accreditation_type to #{type}" do
            accreditation = create :accreditation, 
              campus_ipeds_unitid: crosswalk_approved_public.cross,
              agency_name: agency

            DataCsv.update_with_accreditation
            data = DataCsv.find_by(cross: accreditation.cross)

            expect(data.accreditation_type).to eq(type)
          end
        end
      end  

      context 'with multiple types' do
        it 'chooses NATIONAL over HYBRID' do
          accreditation = create :accreditation, 
            campus_ipeds_unitid: crosswalk_approved_public.cross,
            agency_name: 'ACUPUNCTURE HYBRID'

          accreditation = create :accreditation, 
            campus_ipeds_unitid: crosswalk_approved_public.cross,
            agency_name: 'BIBLICAL NATIONAL'

          accreditation = create :accreditation, 
            campus_ipeds_unitid: crosswalk_approved_public.cross,
            agency_name: 'ACUPUNCTURE HYBRID'

          DataCsv.update_with_accreditation
          data = DataCsv.find_by(cross: accreditation.cross)

          expect(data.accreditation_type).to eq('NATIONAL')    
        end

        it 'chooses REGIONAL over HYBRID' do
          accreditation = create :accreditation, 
            campus_ipeds_unitid: crosswalk_approved_public.cross,
            agency_name: 'ACUPUNCTURE HYBRID'

          accreditation = create :accreditation, 
            campus_ipeds_unitid: crosswalk_approved_public.cross,
            agency_name: 'MIDDLE REGIONAL'

          accreditation = create :accreditation, 
            campus_ipeds_unitid: crosswalk_approved_public.cross,
            agency_name: 'ACUPUNCTURE HYBRID'

          DataCsv.update_with_accreditation
          data = DataCsv.find_by(cross: accreditation.cross)

          expect(data.accreditation_type).to eq('REGIONAL')    
        end

        it 'chooses REGIONAL over NATIONAL' do
          accreditation = create :accreditation, 
            campus_ipeds_unitid: crosswalk_approved_public.cross,
            agency_name: 'BIBLICAL NATIONAL'

          accreditation = create :accreditation, 
            campus_ipeds_unitid: crosswalk_approved_public.cross,
            agency_name: 'MIDDLE REGIONAL'

          accreditation = create :accreditation, 
            campus_ipeds_unitid: crosswalk_approved_public.cross,
            agency_name: 'BIBLICAL NATIONAL'

          DataCsv.update_with_accreditation
          data = DataCsv.find_by(cross: accreditation.cross)

          expect(data.accreditation_type).to eq('REGIONAL')    
        end        
      end
    end

    describe 'when building accreditation_status' do
      context 'and data_csv.accreditation_status is NULL' do
        ['PROBATION', 'SHOW CAUSE'].each do |status|
          it "sets the data_csvs.accreditation_status to #{status}" do
            accreditation = create :accreditation, 
              campus_ipeds_unitid: crosswalk_approved_public.cross,
              agency_name: 'BIBLICAL NATIONAL',
              accreditation_status: status

            DataCsv.update_with_accreditation
            data = DataCsv.find_by(cross: accreditation.cross)

            expect(data.accreditation_status).to eq(status)             
          end
        end
      end

      context 'multiple status for the same accreditation type' do
        it 'chooses PROBATION over NIL' do
          accreditation = create :accreditation, 
            campus_ipeds_unitid: crosswalk_approved_public.cross,
            agency_name: 'BIBLICAL NATIONAL',
            accreditation_status: nil

          accreditation = create :accreditation, 
            campus_ipeds_unitid: crosswalk_approved_public.cross,
            agency_name: 'BIBLICAL NATIONAL',
            accreditation_status: 'PROBATION'

          accreditation = create :accreditation, 
            campus_ipeds_unitid: crosswalk_approved_public.cross,
            agency_name: 'BIBLICAL NATIONAL',
            accreditation_status: nil

          DataCsv.update_with_accreditation
          data = DataCsv.find_by(cross: accreditation.cross)

          expect(data.accreditation_status).to eq('PROBATION')             
        end

        it 'chooses SHOW CAUSE over NIL' do
          accreditation = create :accreditation, 
            campus_ipeds_unitid: crosswalk_approved_public.cross,
            agency_name: 'BIBLICAL NATIONAL',
            accreditation_status: nil

          accreditation = create :accreditation, 
            campus_ipeds_unitid: crosswalk_approved_public.cross,
            agency_name: 'BIBLICAL NATIONAL',
            accreditation_status: 'SHOW CAUSE'

          accreditation = create :accreditation, 
            campus_ipeds_unitid: crosswalk_approved_public.cross,
            agency_name: 'BIBLICAL NATIONAL',
            accreditation_status: nil

          DataCsv.update_with_accreditation
          data = DataCsv.find_by(cross: accreditation.cross)

          expect(data.accreditation_status).to eq('SHOW CAUSE')             
        end

        it 'chooses SHOW CAUSE over PROBATION' do
          accreditation = create :accreditation, 
            campus_ipeds_unitid: crosswalk_approved_public.cross,
            agency_name: 'BIBLICAL NATIONAL',
            accreditation_status: 'PROBATION'

          accreditation = create :accreditation, 
            campus_ipeds_unitid: crosswalk_approved_public.cross,
            agency_name: 'BIBLICAL NATIONAL',
            accreditation_status: 'SHOW CAUSE'

          accreditation = create :accreditation, 
            campus_ipeds_unitid: crosswalk_approved_public.cross,
            agency_name: 'BIBLICAL NATIONAL',
            accreditation_status: 'PROBATION'

          DataCsv.update_with_accreditation
          data = DataCsv.find_by(cross: accreditation.cross)

          expect(data.accreditation_status).to eq('SHOW CAUSE')             
        end
      end   
    end

    describe "when setting data_csv.caution_flag" do
      let(:data) { DataCsv.find_by(cross: accreditation.cross) }

      context "and is institutional, and current" do
        context "and the accreditation_status is not nil" do
          let!(:accreditation) do 
            create :accreditation, 
              campus_ipeds_unitid: crosswalk_approved_public.cross
          end

          before(:each) do
            DataCsv.update_with_accreditation
          end

          it "sets the data_csv.caution_flag true " do
            expect(data.caution_flag).to be_truthy
          end
        end

        context "and the accreditation_status is nil" do
          let!(:accreditation) do 
            create :accreditation, accreditation_status: nil,
              campus_ipeds_unitid: crosswalk_approved_public.cross
          end

          before(:each) do
            DataCsv.update_with_accreditation
          end

          it "leaves the data_csv.caution_flag as it was" do
            expect(data.caution_flag).to be_nil
          end
        end
      end   

      [:not_institutional, :not_current].each do |trait|
        context "and is #{trait.to_s.humanize.downcase}" do
          let!(:accreditation) do 
            create :accreditation, trait,
              campus_ipeds_unitid: crosswalk_approved_public.cross
          end

          before(:each) do
            DataCsv.update_with_accreditation
          end

          it "leaves the data_csv.caution_flag as it was" do
            expect(data.caution_flag).to be_nil
          end
        end 
      end
    end

    describe "when setting data_csv.caution_flag_reason" do
      context "and accreditation is not institutional nor current" do
        before(:each) do
          create :accreditation, :not_institutional, campus_ipeds_unitid: crosswalk_approved_public.cross
          create :accreditation, :not_current, campus_ipeds_unitid: crosswalk_approved_public.cross

          DataCsv.update_with_accreditation
        end

        it "ignores the accreditation" do
          data = DataCsv.find_by(cross: crosswalk_approved_public.cross)
          expect(data.caution_flag_reason).to be_nil
        end
      end
      
      context "and accreditation is institutional and current" do
        context "and accreditation_status or cross are nil" do
          before(:each) do
            create :accreditation, :not_institutional, campus_ipeds_unitid: nil
            create :accreditation, :not_current, campus_ipeds_unitid: crosswalk_approved_public.cross, accreditation_status: nil

            DataCsv.update_with_accreditation
          end

          it "and accreditation cross or status is nil" do
            data = DataCsv.find_by(cross: crosswalk_approved_public.cross)
            expect(data.caution_flag_reason).to be_nil
          end
        end

        context "and the accreditation_status is not nil" do
          let!(:accreditation) do 
            create :accreditation, campus_ipeds_unitid: crosswalk_approved_public.cross, accreditation_status: 'Probation'
          end

          it "sets the data_csv.caution_flag_reason" do
            DataCsv.update_with_accreditation

            data = DataCsv.find_by(cross: crosswalk_approved_public.cross)

            expect(data.caution_flag_reason).to eq("Accreditation (Probation)")
          end

          it "appends accreditation_status grouped by cross" do
            create :accreditation, campus_ipeds_unitid: crosswalk_approved_public.cross, accreditation_status: 'Show Cause'
            DataCsv.update_with_accreditation

            data = DataCsv.find_by(cross: crosswalk_approved_public.cross)
            reason1 = "Accreditation (Probation)"
            reason2 = "Accreditation (Show Cause)"

            expect(data.caution_flag_reason.split(', ')).to contain_exactly(reason1, reason2)
          end

          it "appends to existing caution_flag_reasons" do
            data = DataCsv.find_by(cross: crosswalk_approved_public.cross).update(caution_flag_reason: "A Reason")
            DataCsv.update_with_accreditation

            data = DataCsv.find_by(cross: crosswalk_approved_public.cross)
            str = "A Reason, Accreditation (Probation)"

            expect(data.caution_flag_reason).to eq(str)
          end
        end
      end
    end
  end

  #############################################################################
  ## update_with_arf_gibill
  #############################################################################
  describe "update_with_arf_gibill" do
    let!(:arf_gibill) do 
      create :arf_gibill, 
        facility_code: crosswalk_approved_public.facility_code
    end

    let(:data) { DataCsv.find_by(facility_code: arf_gibill.facility_code) }

    before(:each) do
      DataCsv.update_with_arf_gibill
    end

    describe "when matching" do
      it "matches cross to approved schools in data_csv" do
        expect(data).not_to be_nil
      end
    end

    describe "when copying fields to data_csv" do      
      ArfGibill::USE_COLUMNS.each do |column|
        it "updates the #{column} column" do
          expect(data[column]).to eq(arf_gibill[column])
        end
      end
    end
  end

  #############################################################################
  ## update_with_p911_tf
  #############################################################################
  describe "update_with_p911_tf" do
    let!(:p911_tf) do 
      create :p911_tf, 
        facility_code: crosswalk_approved_public.facility_code 
    end

    let(:data) { DataCsv.find_by(facility_code: p911_tf.facility_code) }

    before(:each) do
      DataCsv.update_with_p911_tf
    end

    describe "when matching" do
      it "is matched by facility_code" do
        expect(data).not_to be_nil
      end
    end

    describe "when copying fields to data_csv" do      
      P911Tf::USE_COLUMNS.each do |column|
        it "updates the #{column} column" do
          expect(data[column]).to eq(p911_tf[column])
        end
      end
    end
  end

  #############################################################################
  ## update_with_p911_yr
  #############################################################################
  describe "with p911_yrs" do
    let!(:p911_yr) { 
      create :p911_yr, 
        facility_code: crosswalk_approved_public.facility_code 
    }

    let(:data) { DataCsv.find_by(facility_code: p911_yr.facility_code) }

    before(:each) do
      DataCsv.update_with_p911_yr
    end

    describe "when matching" do
      it "is matched by facility_code" do
        expect(data).not_to be_nil
      end
    end

    describe "when copying fields to data_csv" do      
      P911Yr::USE_COLUMNS.each do |column|
        it "updates the #{column} column" do
          expect(data[column]).to eq(p911_yr[column])
        end
      end
    end
  end

  #############################################################################
  ## update_with_mou
  #############################################################################
  describe "update_with_mou" do
    let(:data) { DataCsv.find_by(ope6: mou.ope6) }

    describe "when matching" do
      let!(:mou) { create :mou, ope: crosswalk_approved_public.ope }

      before(:each) do
        DataCsv.update_with_mou
      end

      it "is matched by ope6" do
        expect(data).not_to be_nil
      end
    end

    describe "when copying fields to data_csv" do      
      let!(:mou) { create :mou, ope: crosswalk_approved_public.ope }

      let(:data) { DataCsv.find_by(ope6: mou.ope6) }

      before(:each) do
        DataCsv.update_with_mou
      end

      Mou::USE_COLUMNS.each do |column|
        it "updates the #{column} column" do
          expect(data[column]).to eq(mou[column])
        end
      end
    end

    describe "setting data_csv.caution_flag" do
      context "when dod_status is true" do
        let!(:mou) do 
          create :mou, :mou_probation, ope: crosswalk_approved_public.ope
        end

        let(:data) { DataCsv.find_by(ope6: mou.ope6) }

        before(:each) do
          DataCsv.update_with_mou
        end

        it "sets the data_csv.caution_flag true " do
          expect(data.caution_flag).to be_truthy
        end
      end

      context "when dod_status is false" do
        let!(:mou) do 
          create :mou, status: "blah", ope: crosswalk_approved_public.ope
        end

        let(:data) { DataCsv.find_by(ope6: mou.ope6) }

        before(:each) do
          DataCsv.update_with_mou
        end

        it "leaves the data.csv_flag alone" do
          expect(data.caution_flag).to be_nil
        end
      end
    end

    describe "setting the data_csv.caution_flag_reason" do
      let!(:mou) do 
        create :mou, status: "blah", ope: crosswalk_approved_public.ope
      end

      context "when dod_status is false" do
        let(:data) { DataCsv.find_by(ope6: mou.ope6) }

        it "leaves the data.csv_flag alone" do
          DataCsv.update_with_mou

          expect(data.caution_flag_reason).to be_nil
        end
      end

      context "when dod_status is true" do
        let!(:mou) do 
          create :mou, :mou_probation, ope: crosswalk_approved_public.ope
        end

        context 'with a single reason' do
          let(:data) { DataCsv.find_by(ope6: mou.ope6)  }

          it "sets a caution_flag_reason by ope" do
            DataCsv.update_with_mou

            reason = 'DoD Probation For Military Tuition Assistance'
            expect(data.caution_flag_reason).to eq(reason)
          end 
        end

        context 'with a multiple reasons' do
          it "includes the distinct reason only once" do
            create :mou, :mou_probation, ope: crosswalk_approved_public.ope
            DataCsv.update_with_mou

            reason = 'DoD Probation For Military Tuition Assistance'
            expect(data.caution_flag_reason).to eq(reason)
          end
        end

        it "appends to existing caution_flag_reasons" do
          data = DataCsv.find_by(ope6: mou.ope6).update(caution_flag_reason: "A Reason")
          DataCsv.update_with_mou

          data = DataCsv.find_by(ope6: mou.ope6)
          str = "A Reason, DoD Probation For Military Tuition Assistance"

          expect(data.caution_flag_reason).to eq(str)
        end               
      end
    end
  end

  #############################################################################
  ## update_with_scorecard
  #############################################################################
  describe "update_with_scorecard" do
    let!(:scorecard) do 
      create :scorecard, 
        ope: crosswalk_approved_public.ope, 
        cross: crosswalk_approved_public.cross 
    end

    let(:data) { DataCsv.find_by(cross: scorecard.cross) }

    before(:each) do
      DataCsv.update_with_scorecard
    end

    describe "when matching" do
      it "is matched by cross" do
        expect(data).not_to be_nil
      end
    end

    describe "when copying fields to data_csv" do      
      Scorecard::USE_COLUMNS.each do |column|
        it "updates the #{column} column" do
          expect(data[column]).to eq(scorecard[column])
        end
      end
    end
  end

  #############################################################################
  ## update_with_ipeds_ic
  #############################################################################
  describe "update_with_ipeds_ic" do
    let!(:ipeds_ic) do
      create :ipeds_ic, cross: crosswalk_approved_public.cross
    end

    let(:data) { DataCsv.find_by(cross: ipeds_ic.cross) }

    before(:each) do
      DataCsv.update_with_ipeds_ic
    end

    describe "when matching" do
      it "is matched by cross" do
        expect(data).not_to be_nil
      end
    end

    describe "when copying fields to data_csv" do      
      IpedsIc::USE_COLUMNS.each do |column|
        it "updates the #{column} column" do
          expect(data[column]).to eq(ipeds_ic[column])
        end
      end
    end
  end

  #############################################################################
  ## update_with_ipeds_hd
  #############################################################################
  describe "update_with_ipeds_hd" do
    let!(:ipeds_hd) do
      create :ipeds_hd, cross: crosswalk_approved_public.cross
    end

    let(:data) { DataCsv.find_by(cross: ipeds_hd.cross) }

    before(:each) do
      DataCsv.update_with_ipeds_hd
    end

    describe "when matching" do
      it "is matched by cross" do
        expect(data).not_to be_nil
      end
    end

    describe "when copying fields to data_csv" do      
      IpedsHd::USE_COLUMNS.each do |column|
        it "updates the #{column} column" do
          expect(data[column]).to eq(ipeds_hd[column])
        end
      end
    end
  end

  #############################################################################
  ## update_with_ipeds_ic_ay
  #############################################################################
  describe "update_with_ipeds_ic_ay" do
    let!(:ipeds_ic_ay) do 
      create :ipeds_ic_ay, cross: crosswalk_approved_public.cross
    end

    let(:data) { DataCsv.find_by(cross: ipeds_ic_ay.cross) }

    before(:each) do
      DataCsv.update_with_ipeds_ic_ay
    end

    describe "when matching" do
      it "is matched by cross" do
        expect(data).not_to be_nil
      end
    end

    describe "when copying fields to data_csv" do      
      IpedsIcAy::USE_COLUMNS.each do |column|
        it "updates the #{column} column" do
          expect(data[column]).to eq(ipeds_ic_ay[column])
        end
      end
    end
  end

  #############################################################################
  ## update_with_ipeds_ic_py
  #############################################################################
  describe "update_with_ipeds_ic_py" do
    let!(:ipeds_ic_py) do 
      create :ipeds_ic_py, cross: crosswalk_approved_public.cross
    end

    let(:data) { DataCsv.find_by(cross: ipeds_ic_py.cross) }

    describe "when matching" do
      before(:each) do
        DataCsv.update_with_ipeds_ic_py
      end

      it "is matched by cross" do
        expect(data).not_to be_nil
      end
    end

    describe "when copying fields to data_csv" do   
      context "and the values in data_csv are nil" do
        before(:each) do
          DataCsv.update_with_ipeds_ic_py
        end

        IpedsIcPy::USE_COLUMNS.each do |column|
          it "updates the #{column} column" do
            expect(data[column]).to eq(ipeds_ic_py[column])
          end
        end
      end

      context "and the values in data_csv are not nil" do
        before(:each) do
          data.update(
            tuition_in_state: ipeds_ic_py.tuition_in_state - 1,
            tuition_out_of_state: ipeds_ic_py.tuition_out_of_state - 1,
            books: ipeds_ic_py.books - 1
          )

          DataCsv.update_with_ipeds_ic_py
        end

        IpedsIcPy::USE_COLUMNS.each do |column|
          it "does not update the #{column} column" do
            expect(data[column]).not_to eq(ipeds_ic_py[column])
          end
        end
      end
    end
  end

  #############################################################################
  ## update_with_sec702_school
  #############################################################################
  describe "update_with_sec702_school" do
    describe "when matching" do
      let!(:sec702_school) do
        create :sec702_school, sec_702: 'yes',
          facility_code: crosswalk_approved_public.facility_code
      end

      let(:data) do 
        DataCsv.find_by(facility_code: sec702_school.facility_code) 
      end

      before(:each) do
        DataCsv.update_with_sec702_school
      end

      it "is matched by facility_code" do
         expect(data).not_to be_nil
      end
    end

    describe "when copying fields to data_csv" do   
      context "for a public school" do
        context "with sec_702 equal to true" do
          let!(:sec702_school) do
            create :sec702_school, sec_702: 'yes',
              facility_code: crosswalk_approved_public.facility_code
          end

          let(:data) do 
            DataCsv.find_by(facility_code: sec702_school.facility_code) 
          end

          before(:each) do
            DataCsv.update_with_sec702_school
          end

          Sec702School::USE_COLUMNS.each do |column|
            it "updates the #{column} column" do
              expect(data[column]).to eq(sec702_school[column])
            end
          end
        end

        context "with sec_702 equal to nil" do
          let!(:sec702_school) do
            create :sec702_school, sec_702: nil,
              facility_code: crosswalk_approved_public.facility_code
          end

          let(:data) do 
            DataCsv.find_by(facility_code: sec702_school.facility_code) 
          end

          before(:each) do
            DataCsv.update_with_sec702_school
          end

          Sec702School::USE_COLUMNS.each do |column|
            it "does not update the #{column} column" do
              expect(data[column]).to be_nil
            end
          end
        end
      end

      context "for a non-public school" do
        let!(:sec702_school) do
          create :sec702_school, sec_702: 'no',
            facility_code: crosswalk_approved_private.facility_code
        end

        let(:data) do 
          DataCsv.find_by(facility_code: sec702_school.facility_code) 
        end

        before(:each) do
          DataCsv.update_with_sec702_school
        end

        Sec702School::USE_COLUMNS.each do |column|
          it "does not update the #{column} column" do
            expect(data[column]).to be_nil
          end
        end
      end
    end

    describe "setting the data_csv.caution_flag" do
      context "for a public school" do
        context "with sec_702 equal to true" do
          let!(:sec702_school) do
            create :sec702_school, sec_702: 'yes',
              facility_code: crosswalk_approved_public.facility_code
          end

          let(:data) do 
            DataCsv.find_by(facility_code: sec702_school.facility_code) 
          end

          before(:each) do
            DataCsv.update_with_sec702_school
          end

          it "does not set the caution_flag" do
            expect(data.caution_flag).to be_nil
          end          
        end

        context "with sec_702 equal to false" do
          let!(:sec702_school) do
            create :sec702_school, sec_702: 'no',
              facility_code: crosswalk_approved_public.facility_code
          end

          let(:data) do 
            DataCsv.find_by(facility_code: sec702_school.facility_code) 
          end

          before(:each) do
            DataCsv.update_with_sec702_school
          end

          it "sets the caution_flag" do
            expect(data.caution_flag).to be_truthy
          end          
        end        
      end

      context "for a non-public school" do
        let!(:sec702_school) do
          create :sec702_school, sec_702: 'no',
            facility_code: crosswalk_approved_private.facility_code
        end

        let(:data) do 
          DataCsv.find_by(facility_code: sec702_school.facility_code) 
        end

        before(:each) do
          DataCsv.update_with_sec702_school
        end

        it "does not set the caution_flag" do
          expect(data.caution_flag).to be_nil
        end  
      end
    end

    describe "setting the data_csv.caution_flag_reason" do
      context "for a non-public school" do
        let(:data) { DataCsv.find_by(facility_code: sec702_school.facility_code) }
        let!(:sec702_school) { create :sec702_school, sec_702: 'no', facility_code: crosswalk_approved_private.facility_code }
        
        it "does not append data_csv.caution_flag_reason" do
          DataCsv.update_with_sec702_school

          expect(data.caution_flag_reason).to eq(nil)
        end   
      end

      context "for a public school" do
        context "with that is sec_702" do
          let!(:sec702_school) do 
            create :sec702_school, 
              sec_702: 'yes', facility_code: crosswalk_approved_public.facility_code
          end

          it "does not append data_csv.caution_flag_reason" do
            DataCsv.update_with_sec702_school
            data = DataCsv.find_by(facility_code: sec702_school.facility_code)

            expect(data.caution_flag_reason).to eq(nil)
          end   
        end

        context "that is not a sec_702" do
          let(:reason1) { 'Does Not Offer Required In-State Tuition Rates' }

          context "and sec_702 is nil" do 
            let!(:sec702_school) do 
              create :sec702_school, sec_702: nil,
                facility_code: crosswalk_approved_public.facility_code
            end

            it "does not sets the caution_flag_reason when sec_702 is nil" do
              DataCsv.update_with_sec702_school
              data = DataCsv.find_by(facility_code: sec702_school.facility_code)

              expect(data.caution_flag_reason).to be_nil
            end
          end

          context "and sec_702 is 'no'" do 
            let!(:sec702_school) do 
              create :sec702_school, sec_702: 'no',
                facility_code: crosswalk_approved_public.facility_code
            end

            it "sets the caution_flag_reason" do
              DataCsv.update_with_sec702_school
              data = DataCsv.find_by(facility_code: sec702_school.facility_code)

              expect(data.caution_flag_reason).to eq(reason1)
            end

            it "appends to existing caution_flag_reasons" do
              data = DataCsv.find_by(facility_code: sec702_school.facility_code).update(caution_flag_reason: "A Reason")
              DataCsv.update_with_sec702_school
              
              data = DataCsv.find_by(facility_code: sec702_school.facility_code)
              reason2 = "A Reason"

              expect(data.caution_flag_reason.split(', ')).to contain_exactly(reason1, reason2)
            end
          end          
        end
      end
    end
  end

  #############################################################################
  ## update_with_sec702
  #############################################################################
  describe "update_with_sec702" do
    describe "when matching" do
      let!(:sec702) do
        create :sec702, sec_702: 'yes', state: weam_approved_public.state
      end

      let(:data) do 
        DataCsv.find_by(state: sec702.state) 
      end

      before(:each) do
        DataCsv.update_with_sec702_school
      end

      it "is matched by facility_code" do
         expect(data).not_to be_nil
      end
    end

    describe "when copying fields to data_csv" do   
      context "for a public school" do
        context "with sec_702 equal to true" do
          let!(:sec702) do
            create :sec702, sec_702: 'yes', state: weam_approved_public.state
          end

          let(:data) do 
            DataCsv.find_by(state: sec702.state) 
          end

          before(:each) do
            DataCsv.update_with_sec702
          end

          Sec702::USE_COLUMNS.each do |column|
            it "updates the #{column} column" do
              expect(data[column]).to eq(sec702[column])
            end
          end
        end

        context "with sec_702 equal to nil" do
          let!(:sec702) do
            create :sec702, sec_702: nil, state: weam_approved_public.state
          end

          let(:data) do 
            DataCsv.find_by(state: sec702.state) 
          end

          before(:each) do
            DataCsv.update_with_sec702
          end

          Sec702::USE_COLUMNS.each do |column|
            it "does not update the #{column} column" do
              expect(data[column]).to be_nil
            end
          end
        end
      end

      context "for a non-public school" do
        let!(:sec702) do
          create :sec702, sec_702: 'no', state: weam_approved_private.state
        end

        let(:data) do 
          DataCsv.find_by(state: sec702.state) 
        end

        before(:each) do
          DataCsv.update_with_sec702
        end

        Sec702::USE_COLUMNS.each do |column|
          it "does not update the #{column} column" do
            expect(data[column]).to be_nil
          end
        end
      end
    end

    describe "setting the data_csv.caution_flag" do
      context "for a public school" do
        context "with sec_702 equal to true" do
          let!(:sec702) do
            create :sec702, sec_702: 'yes', state: weam_approved_public.state
          end

          let(:data) do 
            DataCsv.find_by(state: sec702.state) 
          end

          before(:each) do
            DataCsv.update_with_sec702
          end

          it "does not set the caution_flag if sec_702 is true" do
            expect(data.caution_flag).to be_nil
          end          
        end

        context "with sec_702 equal to false" do
          context "and data_csv.caution_flag equal to nil" do
            let!(:sec702) do
              create :sec702, sec_702: 'no', state: weam_approved_public.state
            end

            let(:data) do 
              DataCsv.find_by(state: sec702.state) 
            end

            before(:each) do
              DataCsv.update_with_sec702
            end

            it "sets the caution_flag if sec_702 is false" do
              expect(data.caution_flag).to be_truthy
            end          
          end 

          context "and data_csv.caution_flag not equal to nil" do
            let!(:sec702) do
              create :sec702, sec_702: 'no', state: weam_approved_public.state
            end

            let(:data) do 
              DataCsv.find_by(state: sec702.state)
                .update(caution_flag: false)

              DataCsv.find_by(state: sec702.state) 
            end

            before(:each) do
              DataCsv.update_with_sec702
            end

            it "does not set the caution_flag if sec_702 is true" do
              expect(data.caution_flag).not_to be_nil
            end          
          end 
        end    
      end

      context "for a non-public school" do
        let!(:sec702) do
          create :sec702, sec_702: 'yes', state: weam_approved_private.state
        end

        let(:data) do 
          DataCsv.find_by(state: sec702.state) 
        end

        before(:each) do
          DataCsv.update_with_sec702
        end

        it "does not set the caution_flag" do
          expect(data).not_to be_nil
          expect(data.caution_flag).to be_nil
        end  
      end
    end

   describe "setting the data_csv.caution_flag_reason" do
      context "for a non-public school" do
        let(:data) { DataCsv.find_by(state: sec702.state) }
        let!(:sec702) { create :sec702, sec_702: 'no', state: weam_approved_private.state }
        
        it "does not append data_csv.caution_flag_reason" do
          DataCsv.update_with_sec702

          expect(data.caution_flag_reason).to eq(nil)
        end   
      end

      context "for a public school" do
        context "with that is sec_702" do
          let!(:sec702) { create :sec702, sec_702: 'yes', state: weam_approved_public.state }


          it "does not append data_csv.caution_flag_reason" do
            DataCsv.update_with_sec702
            data = DataCsv.find_by(state: sec702.state)

            expect(data.caution_flag_reason).to eq(nil)
          end   
        end

        context "that is not a sec_702" do
          let(:reason1) { 'Does Not Offer Required In-State Tuition Rates' }

          context "and sec_702 is nil" do 
            let!(:sec702) { create :sec702, sec_702: nil, state: weam_approved_public.state }

            it "does not sets the caution_flag_reason when sec_702 is nil" do
              DataCsv.update_with_sec702
              data = DataCsv.find_by(state: sec702.state)

              expect(data.caution_flag_reason).to be_nil
            end
          end

          context "and sec_702 is 'no'" do 
            let!(:sec702) { create :sec702, sec_702: 'no', state: weam_approved_public.state }

            it "sets the caution_flag_reason" do
              DataCsv.update_with_sec702
              data = DataCsv.find_by(state: sec702.state)

              expect(data.caution_flag_reason).to eq(reason1)
            end

            it "appends to existing caution_flag_reasons" do
              data = DataCsv.find_by(state: sec702.state).update(caution_flag_reason: "A Reason")
              DataCsv.update_with_sec702
              
              data = DataCsv.find_by(state: sec702.state)
              reason2 = "A Reason"

              expect(data.caution_flag_reason.split(', ')).to contain_exactly(reason1, reason2)
            end

            it "doesn't append to existing caution_flag_reason from a sec_702 school" do
              sec702_school = create :sec702_school, sec_702: 'no',
                facility_code: weam_approved_public.facility_code
    
              DataCsv.update_with_sec702_school
              DataCsv.update_with_sec702
              
              data = DataCsv.find_by(state: sec702.state)

              expect(data.caution_flag_reason).to eq(reason1)
            end
          end          
        end
      end
    end
  end

  #############################################################################
  ## update_with_settlement
  #############################################################################
  describe "update_with_settlement" do
    describe "when matching" do
      let!(:settlement) do
        create :settlement, cross: crosswalk_approved_public.cross
      end

      let(:data) do 
        DataCsv.find_by(cross: settlement.cross) 
      end

      before(:each) do
        DataCsv.update_with_settlement
      end

      it "is matched by cross" do
         expect(data).not_to be_nil
      end
    end

    describe "setting the data_csv.caution_flag_reason" do
      let!(:settlement) do
        create :settlement, cross: crosswalk_approved_public.cross,
          settlement_description: "A Settlement"
      end

      context 'with a single settlement' do
        let(:data) { DataCsv.find_by(cross: settlement.cross)  }

        it "sets a caution_flag_reason by cross" do
          DataCsv.update_with_settlement

          expect(data.caution_flag_reason).to eq(settlement.settlement_description)
        end 
      end

      context 'with multiple settlements' do
        let(:data) { DataCsv.find_by(cross: settlement.cross)  }

        before(:each) do
          create :settlement, cross: crosswalk_approved_public.cross, 
            settlement_description: "Another Settlement"
        end

        it "concatenates settlement_description by cross" do
          DataCsv.update_with_settlement

          expect(data.caution_flag_reason.split(', ')).to contain_exactly("Another Settlement", "A Settlement")
        end   
      end

      it "appends to existing caution_flag_reasons" do
        data = DataCsv.find_by(cross: settlement.cross).update(caution_flag_reason: "A Reason")
        DataCsv.update_with_settlement

        data = DataCsv.find_by(cross: settlement.cross)
        str = "A Reason, A Settlement"

        expect(data.caution_flag_reason).to eq(str)
      end
    end
  end

  #############################################################################
  ## update_with_hcm
  #############################################################################
  describe "update_with_hcm" do
    describe "when matching" do
      let!(:hcm) do
        create :hcm, ope: crosswalk_approved_public.ope
      end

      let(:data) do 
        DataCsv.find_by(ope6: hcm.ope6) 
      end

      before(:each) do
        DataCsv.update_with_hcm
      end

      it "is matched by ope6" do
         expect(data).not_to be_nil
      end
    end

    describe "setting the data_csv.caution_flag" do
      let!(:hcm) do
        create :hcm, ope: crosswalk_approved_public.ope
      end

      let(:data) do 
        DataCsv.find_by(ope6: hcm.ope6) 
      end

      before(:each) do
        DataCsv.update_with_hcm
      end

      it "with an hcm_reason" do
        expect(data.caution_flag).to be_truthy
      end          
    end

    describe "setting the data_csv.caution_flag_reason" do
      let!(:hcm) do
        create :hcm, ope: crosswalk_approved_public.ope, hcm_reason: "An HCM Reason"
      end

      context 'with a single reason' do
        it "sets a caution_flag_reason by cross" do
          DataCsv.update_with_hcm
          data = DataCsv.find_by(ope6: hcm.ope6) 

          str = "Heightened Cash Monitoring (#{hcm.hcm_reason})"
          expect(data.caution_flag_reason).to eq(str)
        end 
      end

      context 'with multiple reasons' do
        let(:data) { DataCsv.find_by(ope6: hcm.ope6)  }

        before(:each) do
          create :hcm, ope: crosswalk_approved_public.ope, hcm_reason: "Another HCM Reason"
          DataCsv.update_with_hcm
        end

        it "concatenates hcm_reason by cross" do
          reason1 = "Heightened Cash Monitoring (An HCM Reason)"
          reason2 = "Heightened Cash Monitoring (Another HCM Reason)"
          expect(data.caution_flag_reason.split(', ')).to contain_exactly(reason1, reason2)
        end   
      end

      it "appends to existing caution_flag_reasons" do
        data = DataCsv.find_by(ope6: hcm.ope6).update(caution_flag_reason: "A Reason")
        DataCsv.update_with_hcm

        data = DataCsv.find_by(ope6: hcm.ope6)
        str = "A Reason, Heightened Cash Monitoring (An HCM Reason)"

        expect(data.caution_flag_reason).to eq(str)
      end    
    end
  end

  #############################################################################
  ## update_with_complaint
  #############################################################################
  describe "update_with_complaint" do
    let(:data) { DataCsv.find_by(facility_code: complaint.facility_code) }
    let(:complaint) { Complaint.find_by(facility_code: crosswalk_approved_public.facility_code) }

    before(:each) do
      create :complaint, :all_issues,
        facility_code: crosswalk_approved_public.facility_code 

      Complaint.update_sums_by_fac
    end

    describe "when updating ope complaints" do
      it "calls update_sums_by_ope6" do
        expect(Complaint).to receive(:update_sums_by_ope6)
        DataCsv.update_with_complaint
      end
    end

    describe "when matching" do
      it "is matched by facility_code" do
        DataCsv.update_with_complaint
        
        expect(data).not_to be_nil
      end
    end

    describe "when copying fields to data_csv" do      
      Complaint::USE_COLUMNS.each do |column|
        it "updates the #{column} column" do
          expect{ DataCsv.update_with_complaint }.to change{ 
            DataCsv.find_by(facility_code: complaint.facility_code)[column] 
          }
        end
      end
    end
  end

  #############################################################################
  ## update_with_outcome
  #############################################################################
  describe "update_with_outcome" do
    let!(:outcome) { create :outcome, facility_code: crosswalk_approved_public.facility_code }
    let(:data) { DataCsv.find_by(facility_code: outcome.facility_code) }

    before(:each) do
      DataCsv.update_with_outcome
    end

    describe "when matching" do
      it "is matched by facility_code" do
        expect(data).not_to be_nil
      end
    end

    describe "when copying fields to data_csv" do      
      Outcome::USE_COLUMNS.each do |column|
        it "updates the #{column} column" do
          expect(data[column]).to eq(outcome[column])
        end
      end
    end
  end
end
