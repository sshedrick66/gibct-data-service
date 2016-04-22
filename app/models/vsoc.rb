class Vsoc < ActiveRecord::Base
  include Standardizable

  validates :facility_code, presence: true, uniqueness: true
  
  USE_COLUMNS = [:vetsuccess_name, :vetsuccess_email]

  override_setters :facility_code, :institution, :vetsuccess_name, 
    :vetsuccess_email
end
