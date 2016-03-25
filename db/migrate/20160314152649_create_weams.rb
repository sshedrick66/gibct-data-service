class CreateWeams < ActiveRecord::Migration
  def change
    create_table :weams do |t|
    	t.string :facility_code, null: false
    	t.string :institution, null: false
    	t.string :city
    	t.string :state
    	t.string :zip
    	t.string :country
    	t.string :accredited
			t.string :bah
			t.string :poe
			t.string :yr
      t.string :ojt_indicator
      t.string :correspondence_indicator
      t.string :flight_indicator

      t.timestamps null: false
      
      t.index :facility_code, unique: true
      t.index :institution
     	t.index :city
      t.index :state
      t.index :country
    end
  end
end